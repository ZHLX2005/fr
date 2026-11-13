#!/usr/bin/env node
// nx-kv 契约包 ref 自动对齐（fr 侧）
//
// 背景：`nx_kv_client` 走 git 依赖并锁 40 位 sha —— 这是刻意选的（锁提交而不是
// tag：annotated tag 的 rev-parse 给的是 tag 对象，而 pub 的 resolved-ref 要提交；
// 锁 sha 也让 pubspec 与 pubspec.lock 写的是同一个值，不存在「tag 被移动」的重放歧义）。
// 代价是每次 nx-kv 发版，fr 都得有人把那个 40 位 sha 改一遍。本脚本把那一步自动化。
//
// 它只做三件事：解析 nx-kv 最新 tag → 与 pubspec 里的 ref 比对 → 不同则改写 ref
// （顺带把上面那句「当前 = nx-kv vX.Y.Z」注释改对）。改 pubspec.lock、跑 analyze、
// 开 PR 都在工作流里，不在脚本里 —— 脚本保持纯文本操作，本地可单跑。
//
// 用法：
//   node scripts/nxkv-sync.mjs                     # 最新 tag，不同就改写
//   node scripts/nxkv-sync.mjs --check             # 只报告，不落盘
//   node scripts/nxkv-sync.mjs --sha <40位 sha>    # 指定目标提交
//   node scripts/nxkv-sync.mjs --mode hash-only    # 指纹没变就不算「要 bump」
//   node scripts/nxkv-sync.mjs --repo <url|路径>   # nx-kv 仓库（默认公开 https）
//   node scripts/nxkv-sync.mjs --root <目录>       # fr 仓库根（默认 cwd）
//
// 退出码：0 = 正常（无论有没有改动，看 changed 输出）；1 = 出错。
// 在 CI 里会把 from_sha / sha / version / hash / changed 等写进 $GITHUB_OUTPUT。

import { execFileSync } from 'node:child_process';
import { appendFileSync, existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const DEFAULT_REPO = 'https://github.com/On-DevPlan/nx-kv.git';

// ---------- 参数 ----------
function parseArgs(argv) {
  const out = { repo: DEFAULT_REPO, root: process.cwd(), mode: 'any', check: false, sha: '' };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--check') out.check = true;
    else if (a === '--repo') out.repo = argv[++i];
    else if (a === '--root') out.root = argv[++i];
    else if (a === '--mode') out.mode = argv[++i];
    else if (a === '--sha') out.sha = argv[++i];
    else if (a === '--help' || a === '-h') out.help = true;
    else throw new Error(`未知参数：${a}`);
  }
  if (!['any', 'hash-only'].includes(out.mode)) throw new Error(`--mode 只能是 any / hash-only，收到 ${out.mode}`);
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

function git(args, opts = {}) {
  return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts }).trim();
}

// ---------- 版本比较 ----------
const SEMVER = /^v(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/;

function parseTag(tag) {
  const m = SEMVER.exec(tag);
  if (!m) return null;
  return { tag, major: +m[1], minor: +m[2], patch: +m[3], pre: m[4] || '' };
}

function cmpTag(a, b) {
  if (a.major !== b.major) return a.major - b.major;
  if (a.minor !== b.minor) return a.minor - b.minor;
  if (a.patch !== b.patch) return a.patch - b.patch;
  // 正式版 > 预发布版；两个预发布版按字符串比（够用）
  if (a.pre === b.pre) return 0;
  if (!a.pre) return 1;
  if (!b.pre) return -1;
  return a.pre < b.pre ? -1 : 1;
}

// ---------- 解析 nx-kv 的 tag → 提交 ----------
// 注意 annotated tag：`git ls-remote` 同时给 `refs/tags/v1.2.3`（tag 对象）
// 和 `refs/tags/v1.2.3^{}`（它指向的提交）。要的是后者 —— pub 的 resolved-ref
// 是提交 sha，锁成 tag 对象会 fetch 不到。
function remoteTags(repo) {
  const text = git(['ls-remote', '--tags', repo]);
  const map = new Map();
  for (const line of text.split('\n')) {
    const [sha, ref] = line.trim().split(/\s+/);
    if (!sha || !ref) continue;
    const m = /^refs\/tags\/(.+?)(\^\{\})?$/.exec(ref);
    if (!m) continue;
    const tag = m[1];
    const entry = map.get(tag) || {};
    if (m[2]) entry.commit = sha;
    else entry.object = sha;
    map.set(tag, entry);
  }
  return map;
}

function localTags(dir) {
  const map = new Map();
  for (const tag of git(['-C', dir, 'tag', '-l', 'v*']).split('\n').filter(Boolean)) {
    try {
      map.set(tag, { commit: git(['-C', dir, 'rev-parse', `${tag}^{commit}`]), object: git(['-C', dir, 'rev-parse', tag]) });
    } catch {
      /* 指向不存在的对象，跳过 */
    }
  }
  return map;
}

function latestTag(repo) {
  const isDir = existsSync(repo) && statSync(repo).isDirectory();
  const map = isDir ? localTags(repo) : remoteTags(repo);
  const cands = [...map.keys()].map(parseTag).filter(Boolean).filter((t) => !t.pre).sort(cmpTag);
  if (!cands.length) throw new Error(`在 ${repo} 里没找到 v* 正式版 tag`);
  const best = cands[cands.length - 1];
  const entry = map.get(best.tag);
  return { tag: best.tag, version: best.tag.slice(1), sha: entry.commit || entry.object };
}

// ---------- 读某个提交里的契约快照 ----------
// 用「临时仓库 + fetch 单个 ref」而不是 raw.githubusercontent：只依赖 git，
// 本地路径与 https 两种源走同一条代码路径，行为可本地复现。
function contractAt(repo, refSpec) {
  const dir = mkdtempSync(join(tmpdir(), 'nxkv-sync-'));
  try {
    git(['-C', dir, 'init', '-q']);
    git(['-C', dir, 'remote', 'add', 'origin', repo]);
    git(['-C', dir, 'fetch', '-q', '--depth', '1', 'origin', refSpec], { stdio: ['ignore', 'pipe', 'pipe'] });
    const json = git(['-C', dir, 'show', 'FETCH_HEAD:contract/contract.json']);
    return JSON.parse(json);
  } catch {
    return null; // 老版本可能还没有契约产物
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// ---------- 改写 pubspec.yaml ----------
const REF_LINE = /^(\s+ref:\s*)([0-9a-f]{40})(\s*)$/m;

function rewritePubspec(text, { fromSha, toSha, toVersion }) {
  // 只在 nx_kv_client 这一块里动，避免误伤别的依赖（.pub-cache 等不受影响，纯文本替换）
  const blockStart = text.indexOf('\n  nx_kv_client:');
  if (blockStart < 0) throw new Error('pubspec.yaml 里找不到 nx_kv_client 块');
  const rest = text.slice(blockStart + 1);
  const blockEnd = rest.search(/\n\S/); // 下一个顶格行 = 块结束
  const block = blockEnd < 0 ? rest : rest.slice(0, blockEnd);
  const next = block.replace(REF_LINE, (_, head, _sha, tail) => `${head}${toSha}${tail}`);
  if (next === block) throw new Error(`nx_kv_client 块里没找到 40 位 ref（当前 ref 期望是 ${fromSha}）`);
  if (!next.includes(toSha)) throw new Error('替换后仍不含目标 sha，放弃');
  let out = text.slice(0, blockStart + 1) + next + (blockEnd < 0 ? '' : rest.slice(blockEnd));
  // 注释里的「当前 = nx-kv vX.Y.Z」跟着走，否则一个月后没人信这行注释
  out = out.replace(/(#\s*锁 ref[^\n]*当前 = nx-kv v)\d+\.\d+\.\d+/, `$1${toVersion}`);
  return out;
}

// ---------- 输出 ----------
function emit(pairs) {
  const file = process.env.GITHUB_OUTPUT;
  if (!file) return;
  const lines = Object.entries(pairs).map(([k, v]) => `${k}=${String(v ?? '')}`);
  appendFileSync(file, lines.join('\n') + '\n');
}

// ---------- main ----------
function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    log('node scripts/nxkv-sync.mjs [--check] [--sha <sha>] [--mode any|hash-only] [--repo <url|路径>] [--root <目录>]');
    return;
  }

  const root = resolve(args.root);
  const pubspecPath = join(root, 'pubspec.yaml');
  const text = readFileSync(pubspecPath, 'utf8');
  const cur = REF_LINE.exec(text.slice(text.indexOf('\n  nx_kv_client:')));
  if (!cur) throw new Error('pubspec.yaml 的 nx_kv_client 块里没有 40 位 ref');

  const target = group('解析 nx-kv 目标提交', () => {
    if (args.sha) {
      if (!/^[0-9a-f]{40}$/.test(args.sha)) throw new Error(`--sha 不是 40 位十六进制：${args.sha}`);
      const snap = contractAt(args.repo, args.sha);
      // 只给了 sha 时没有 tag 名：用快照里的版本号兜一个 vX.Y.Z（PR 标题要用）
      const version = snap?.version || '';
      return { tag: version ? `v${version}` : args.sha.slice(0, 7), version, sha: args.sha, snapshot: snap };
    }
    const t = latestTag(args.repo);
    return { ...t, snapshot: null };
  });

  const fromSha = cur[2];
  const changed = fromSha !== target.sha;

  const snapNew = target.snapshot || contractAt(args.repo, target.tag || target.sha);
  const snapOld = fromSha === target.sha ? snapNew : contractAt(args.repo, fromSha);
  const hashNew = snapNew?.hash || '';
  const hashOld = snapOld?.hash || '';
  const hashChanged = Boolean(hashNew && hashOld && hashNew !== hashOld);
  const versionNew = target.version || snapNew?.version || '';

  log(`nx-kv 目标   ${target.tag || '(指定 sha)'} → ${target.sha.slice(0, 7)}  版本 ${versionNew || '?'}  指纹 ${hashNew || '?'}`);
  log(`pubspec 当前 ${fromSha.slice(0, 7)}  指纹 ${hashOld || '?'}`);

  // hash-only 模式：指纹没变就不打扰（版本号变化只影响端侧诊断信息）
  const skipByMode = args.mode === 'hash-only' && changed && hashOld && hashNew && !hashChanged;
  if (!changed || skipByMode) {
    log(changed ? '::notice::版本变了但契约指纹没变（hash-only 模式），跳过' : '::notice::已是最新，无需 bump');
    emit({ changed: 'false', reason: changed ? 'hash-unchanged' : 'up-to-date', sha: target.sha, from_sha: fromSha });
    return;
  }

  const updated = rewritePubspec(text, { fromSha, toSha: target.sha, toVersion: versionNew });
  if (args.check) {
    log('::notice::--check：只报告，未落盘');
  } else {
    writeFileSync(pubspecPath, updated, 'utf8');
    log(`已改写 pubspec.yaml：${fromSha.slice(0, 7)} → ${target.sha.slice(0, 7)}${hashChanged ? '（契约指纹变了，端侧必须看 diff）' : '（仅版本号，纯对齐）'}`);
  }

  emit({
    changed: 'true',
    tag: target.tag,
    sha: target.sha,
    from_sha: fromSha,
    version: versionNew,
    from_version: snapOld?.version || '',
    hash: hashNew,
    from_hash: hashOld,
    hash_changed: String(hashChanged),
  });
}

try {
  main();
} catch (err) {
  log(`::error::${err.message}`);
  process.exit(1);
}
