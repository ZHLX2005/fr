#!/usr/bin/env node
// nx-kv 契约包：判断 fr 的 lock 有没有跟到 nx-kv 的分支尖（fr 侧）
//
// pubspec.yaml 里 `nx_kv_client` 跟的是 nx-kv 的 main（**不锁 sha**），真正钉住版本的
// 是 pubspec.lock 的 resolved-ref。实测行为（两行就能验）：
//   pub get                  → 不动 lock 的 resolved-ref，构建可重现
//   pub upgrade nx_kv_client → 才跟到分支尖
// 所以「要不要更新」必须有人定期判断 —— 本脚本只做判断（不写任何文件），更新交给
// workflow 里的 `flutter pub upgrade`。判断很便宜：一条 git ls-remote（~0.3s），
// 没变化时连 Flutter 都不用装。
//
// 用法：
//   node scripts/nxkv-contract.mjs                        # 判定 main 是否领先 lock
//   node scripts/nxkv-contract.mjs --mode hash-only       # 指纹没变就不算要更新
//   node scripts/nxkv-contract.mjs --ref main             # 换分支/标签
//   node scripts/nxkv-contract.mjs --from <sha> --to <sha>  # 手工指定两端
//   node scripts/nxkv-contract.mjs --repo <url|路径>      # nx-kv 仓库（默认公开 https）
//   node scripts/nxkv-contract.mjs --root <目录>          # fr 仓库根（默认 cwd）
//
// 退出码：0 = 正常（无论更不更新，看 changed 输出）；1 = 出错。
// CI 里会把 changed / from_sha / sha / version / hash / hash_changed 写进 $GITHUB_OUTPUT。

import { execFileSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const DEFAULT_REPO = 'https://github.com/On-DevPlan/nx-kv.git';

// ---------- 参数 ----------
function parseArgs(argv) {
  const out = { repo: DEFAULT_REPO, root: process.cwd(), mode: 'any', ref: 'main', from: '', to: '' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--repo') out.repo = argv[++i];
    else if (a === '--root') out.root = argv[++i];
    else if (a === '--mode') out.mode = argv[++i];
    else if (a === '--ref') out.ref = argv[++i];
    else if (a === '--from') out.from = argv[++i];
    else if (a === '--to') out.to = argv[++i];
    else if (a === '--help' || a === '-h') out.help = true;
    else throw new Error(`未知参数：${a}`);
  }
  if (!['any', 'hash-only'].includes(out.mode)) throw new Error(`--mode 只能是 any / hash-only，收到 ${out.mode}`);
  for (const k of ['from', 'to']) {
    if (out[k] && !/^[0-9a-f]{7,40}$/.test(out[k])) throw new Error(`--${k} 不像提交 sha：${out[k]}`);
  }
  return out;
}

const log = (...a) => console.log(...a);
const group = (title, fn) => {
  log(`::group::${title}`);
  try {
    return fn();
  } finally {
    log('::endgroup::');
  }
};

function git(args) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

const isDir = (p) => existsSync(p) && statSync(p).isDirectory();

// ---------- 锁里现在钉在哪 ----------
// pubspec.lock 的 nx_kv_client 块长这样：
//   nx_kv_client:
//     dependency: "direct main"
//     description:
//       path: "contract/dart"
//       ref: main
//       resolved-ref: "<sha>"
//     source: git
//     version: "0.52.0"
function readLock(root) {
  const text = readFileSync(join(root, 'pubspec.lock'), 'utf8');
  const block = /^ {2}nx_kv_client:\n([\s\S]*?)(?=\n {2}\S)/m.exec(text);
  if (!block) throw new Error('pubspec.lock 里没有 nx_kv_client 块（先跑一次 flutter pub get）');
  const body = block[1];
  const sha = /resolved-ref:\s*"([0-9a-f]{40})"/.exec(body)?.[1];
  const version = /\n\s+version:\s*"([^"]+)"/.exec(body)?.[1] || '';
  if (!sha) throw new Error('pubspec.lock 的 nx_kv_client 块里没有 resolved-ref');
  return { sha, version };
}

// ---------- 分支/ref → 提交 ----------
// annotated tag 会同时返回 `refs/tags/vX`（tag 对象）和 `refs/tags/vX^{}`（提交），
// 要的是后者；分支只有一条。所以按 ref 名精确挑，不猜。
function resolveRef(repo, ref) {
  if (/^[0-9a-f]{40}$/.test(ref)) return ref;
  if (isDir(repo)) return git(['-C', repo, 'rev-parse', `${ref}^{commit}`]);

  const parsed = git(['ls-remote', repo, ref])
    .split('\n')
    .filter(Boolean)
    .map((l) => {
      const [sha, name] = l.split(/\s+/);
      return { sha, name };
    });
  const picked =
    parsed.find((p) => p.name === `refs/heads/${ref}`) ||
    parsed.find((p) => p.name === `refs/tags/${ref}^{}`) ||
    parsed.find((p) => p.name === `refs/tags/${ref}`);
  if (!picked) throw new Error(`在 ${repo} 里找不到 ref：${ref}`);
  return picked.sha;
}

// ---------- 读某个提交里的契约快照 ----------
// 用「临时仓库 + fetch 单个 ref」而不是 raw.githubusercontent：只依赖 git，
// 本地路径源与 https 源走同一条代码路径，本机就能把逻辑跑通。
function contractAt(repo, refSpec) {
  const dir = mkdtempSync(join(tmpdir(), 'nxkv-contract-'));
  try {
    git(['-C', dir, 'init', '-q']);
    git(['-C', dir, 'remote', 'add', 'origin', repo]);
    git(['-C', dir, 'fetch', '-q', '--depth', '1', 'origin', refSpec]);
    return JSON.parse(git(['-C', dir, 'show', 'FETCH_HEAD:contract/contract.json']));
  } catch {
    return null; // 老提交可能还没有契约产物
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function emit(pairs) {
  const file = process.env.GITHUB_OUTPUT;
  if (!file) return;
  appendFileSync(file, Object.entries(pairs).map(([k, v]) => `${k}=${String(v ?? '')}`).join('\n') + '\n');
}

// ---------- main ----------
function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    log('node scripts/nxkv-contract.mjs [--ref main] [--mode any|hash-only] [--from <sha>] [--to <sha>] [--repo <url|路径>] [--root <目录>]');
    return;
  }

  const root = resolve(args.root);
  const lock = readLock(root);
  const fromSha = args.from || lock.sha;
  const fromVersion = args.from ? '' : lock.version;

  const toSha = group(`解析 nx-kv 的 ${args.ref}`, () => args.to || resolveRef(args.repo, args.ref));

  log(`lock 钉在    ${fromSha.slice(0, 7)}${fromVersion ? `  版本 ${fromVersion}` : ''}`);
  log(`nx-kv 尖端   ${toSha.slice(0, 7)}（${args.ref}）`);

  if (fromSha === toSha) {
    log('::notice::lock 已经跟到分支尖，无需更新');
    emit({ changed: 'false', reason: 'up-to-date', sha: toSha, from_sha: fromSha });
    return;
  }

  const snapTo = group('对账契约指纹', () => contractAt(args.repo, toSha));
  const snapFrom = args.to ? null : contractAt(args.repo, fromSha);
  const hashTo = snapTo?.hash || '';
  const hashFrom = snapFrom?.hash || '';
  const hashChanged = Boolean(hashTo && hashFrom && hashTo !== hashFrom);
  const versionTo = snapTo?.version || '';

  // hash-only：分支尖只是普通提交（没碰契约产物）就不打扰
  if (args.mode === 'hash-only' && hashFrom && hashTo && !hashChanged) {
    log('::notice::分支尖有变化，但契约指纹没变（hash-only 模式），跳过');
    emit({ changed: 'false', reason: 'hash-unchanged', sha: toSha, from_sha: fromSha });
    return;
  }

  log(
    `需要更新：${fromSha.slice(0, 7)} → ${toSha.slice(0, 7)}` +
      `　版本 ${fromVersion || snapFrom?.version || '?'} → ${versionTo || '?'}` +
      `　指纹 ${hashFrom || '?'} → ${hashTo || '?'}${hashChanged ? '（变了）' : '（没变）'}`
  );

  emit({
    changed: 'true',
    ref: args.ref,
    sha: toSha,
    from_sha: fromSha,
    version: versionTo,
    from_version: fromVersion || snapFrom?.version || '',
    hash: hashTo,
    from_hash: hashFrom,
    hash_changed: String(hashChanged),
  });
}

try {
  main();
} catch (err) {
  log(`::error::${err.message}`);
  process.exit(1);
}
