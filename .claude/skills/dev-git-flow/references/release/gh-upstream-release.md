---
name: gh-upstream-release
description: |
  Fork 模式下，把当前分支领先 upstream/master 的多个 commit 压缩成一个，
  推送到 `upstream` 远端，再 `gh pr create` + `--squash` 合并到主分支的端到端 SOP。
  触发场景：用户说"压缩领先 commit 再发版"、"squash 后推到 upstream 然后 PR"、
  "用 gh 推到 upstream master"、"把当前分支发版"、"open PR against upstream"、
  明确给出 squash + push + gh pr create 序列时。
  适用前提：本地有 `origin`（自己的 fork）和 `upstream`（canonical 仓库）两个 remote；
  当前分支相对 `upstream/master` 已有 N 个领先 commit（N ≥ 1）。
---
# gh-upstream-release

把"压缩领先 commit → force push → gh pr create → squash merge"打包成可重复执行的 SOP。

## 0. 适用前提检查（必做）

```bash
git remote -v
git symbolic-ref --short refs/remotes/upstream/HEAD 2>/dev/null
```

预期：能同时看到 `origin`（fork）和 `upstream`（canonical）。

- 只有 `origin` → **不要继续**，用户可能尚未添加 upstream 远端，先 `git remote add upstream <url>`。
- 只有 `upstream`（没 fork）→ 这个 skill 不适用，**改用纯 `git push` 即可**。

## 1. 检测领先主分支多少 commit

```bash
# 领先数 n
git rev-list --count upstream/master..HEAD

# 领先列表（直观看到要压缩哪些 commit）
git log --oneline upstream/master..HEAD

# 当前分支名（步骤 3/4 用）
git branch --show-current
```

**判断**：

- `n == 0` → 没有领先 commit，**不要执行 squash**，直接走原 skill 的"普通 push + PR"流程。
- `n == 1` → 只有一个 commit，理论上不必 squash；但若用户明确要求 squash，仍走步骤 2。
- `n ≥ 2` → 标准场景，继续步骤 2。

> ⚠️ **注意**：master/main base 的判定在步骤 4 里做；这里 `upstream/master` 只是用作"领先起点"，
> 若实际 base 是 `main`，把命令里的 `master` 换成 `main` 即可。

## 2. soft reset + 压缩成一个 commit

```bash
N=$(git rev-list --count upstream/master..HEAD)
git reset --soft upstream/master

# 此时所有领先 commit 的内容都暂存在 staged changes
git commit -m "<合并后的标题>"
```

**commit 信息建议**：

- 走 Conventional Commits：`<type>(<scope>): <desc>`，例如 `feat(notion): batch upload overflow handling`。
- 若用户原 N 个 commit 信息重要，可在 squash 前用 `git log upstream/master..HEAD --format=%s` 摘出要点，
  作为合并 commit 的正文（`git commit` 时不带 `-m` 进入编辑器写多行）。

**示例（多行正文）**：

```bash
git reset --soft upstream/master
git commit   # 进入编辑器，Subject + Body 写完整描述
```

## 3. 推送到 upstream 当前分支

```bash
git push upstream HEAD --force-with-lease
```

**为什么 force**：

- soft reset 后会产生全新 SHA，原远端 SHA 不再是 HEAD 的祖先，普通 push 会被拒。
- 用 `--force-with-lease` 而非 `--force`：若远端在这期间被他人推过新 commit，会拒绝覆盖（更安全）。

**失败诊断**：

| 报错                                  | 根因                          | 修法                                                                          |
| ------------------------------------- | ----------------------------- | ----------------------------------------------------------------------------- |
| `Permission denied (publickey)`     | SSH key 未配到 GitHub         | `ssh-add -l` 看 key 列表；重新 `gh auth login` 选 SSH                     |
| `Could not resolve host github.com` | 网络/代理问题                 | 换 WiFi / 关代理 / 等几秒重试                                                 |
| `rejected: non-fast-forward`        | 远端有更新或被他人 force push | `git fetch upstream <branch>` 检查；确认无人提交后再 `--force-with-lease` |
| `[remote rejected] (stale info)`    | with-lease 检测到远端更新     | 先`git fetch` 看远端新提交，**与他人确认后再 force**                  |
| `repository not found`              | upstream URL 错或无权限       | `git remote -v` 检查，确认有 push 权限                                      |

> **不要用 `git push -f`**：with-lease 是安全版，仅在你确认远端状态时使用。

## 4. gh 开 PR + 压缩合并到主分支

```bash
# 1. 解析 upstream org/repo
UPSTREAM=$(git remote get-url upstream | sed -E 's#.*github.com[:/](.+)/.+(\.git)?$#\1#')
BRANCH=$(git branch --show-current)

# 2. 自动探测 base 分支：upstream/HEAD → main → master
BASE=$(git symbolic-ref --short refs/remotes/upstream/HEAD 2>/dev/null | sed 's#upstream/##')
if [ -z "$BASE" ]; then
  BASE=$(git remote show upstream 2>/dev/null | sed -n 's/.*HEAD branch: //p')
fi
case "$BASE" in
  main|master) ;;
  *) BASE="master" ;;     # 白名单兜底
esac

# 3. 验证登录
gh auth status
```

**开 PR**：

```bash
gh pr create \
  --repo "$UPSTREAM" \
  --base "$BASE" --head "$BRANCH" \
  --title "<PR 标题>" \
  --body  "<PR 正文>"
```

**参数推断规则**（按优先级）：

1. **`--repo`** — 从 `git remote get-url upstream` 解析。例如 `git@github.com:ZHLX2005/fr.git` → `ZHLX2005/fr`。
2. **`--base`** — 按上面 BASE 变量自动探测（main 优先，master 兜底）。
3. **`--head`** — 当前分支名（`git branch --show-current`）。
4. **`--title`** — 优先用用户给的话；未指定时用 `<branch> → <base> (squash of N commits)`。
5. **`--body`** — 默认含原 N 个 commit 的标题列表（从 `git log upstream/master..HEAD` 摘），
   让 reviewer 看到 squash 前发生过什么。

**直接 squash merge**（流程要求"压缩合并到主分支"，不再问"等 CI / 立刻合"）：

```bash
gh pr merge <num> --repo "$UPSTREAM" --squash --delete-branch
```

`--delete-branch` 会同时删远端 head 分支（squash 后安全，新 squash commit 已合并进 base）。

**失败诊断**：

| 报错                                               | 根因                       | 修法                                                                    |
| -------------------------------------------------- | -------------------------- | ----------------------------------------------------------------------- |
| `HTTP 401: Bad credentials`                      | keyring 里的 gh token 失效 | `gh auth status` 确认 → 用户跑 `gh auth login`（不可自动化，阻塞） |
| `HTTP 422: Validation Failed`                    | 已有同 head→base 的 PR    | `gh pr list --head <branch>` 查现有 PR URL 给用户                     |
| `GraphQL: ... could not resolve to a Repository` | `--repo` 写错            | 从`git remote get-url upstream` 重新解析                              |
| `TLS handshake timeout`                          | 临时网络                   | 等几秒重试；不行则`gh pr create --web` 走浏览器兜底                   |

**`gh pr create --web` 兜底**：

如果 CLI 一直报错，**不要重试超过 1 次**。改用：

```bash
gh pr create --web --repo "$UPSTREAM" --base "$BASE" --head "$BRANCH"
```

这会打开浏览器预填好表单，让用户手动点确认。

## 5. 总结显示 PR 具体内容

```bash
gh pr view <num> --repo "$UPSTREAM" \
  --json number,title,state,url,body,author,createdAt,mergedAt,
         headRefName,baseRefName,mergeCommit,additions,deletions,
         changedFiles,files
```

字段说明：

- `number / title / url` — PR 标识
- `state` — OPEN / MERGED / CLOSED
- `body` — PR 描述（含原 N 个 commit 摘要）
- `author` — `{login, name}`
- `createdAt / mergedAt` — 时间戳
- `headRefName / baseRefName` — 分支对（squash 前的 head 与 base）
- `mergeCommit` — squash 合并后的新 commit `{oid, messageHeadline, messageBody, committedDate}`
- `additions / deletions / changedFiles` — 改动统计
- `files` — 改动文件清单（每项含 `path, additions, deletions, changeType`）

**回报格式**（按 `rules/claude-scholar-core.md` 的"任务完成摘要"格式）：

```markdown
📋 PR 合并信息
| 项 | 值 |
|---|---|
| PR | https://github.com/<org>/<repo>/pull/<num> |
| 状态 | MERGED ✅ |
| 源分支 → 目标分支 | <branch> → <base> |
| Squash 策略 | N commits → 1 commit |
| 合并方式 | squash |
| 合并者 | <gh user> |
| 合并时间 | <ISO timestamp> |
| Squash commit | <sha> "<headline> (#<num>)" |
| 改动统计 | +<X> / -<Y>，<Z> files changed |

📊 upstream <base> HEAD
<show 3 commits with `git log --oneline upstream/<base> -3`>

🗂 PR 改动文件清单
| 文件 | +/- | 变更类型 |
|---|---|---|
| <path1> | +X / -Y | modified |
| <path2> | +X / -Y | added |
| ... | ... | ... |

💡 Next Steps
1. 本地 base 同步：`git fetch upstream <base>` → `git pull --rebase upstream <base>`
2. 本地 head 分支清理：`git branch -d <branch>`（squash 合并后远端已删）
3. CI 后置检查：关注 Actions 页面，确认 squash 合并后无回归
```

## 6. 验证清单

- [ ] `git remote -v` 看到 origin + upstream 两个 remote
- [ ] 步骤 1 确认 `n ≥ 2`（squash 才有意义）
- [ ] `git status` 在 soft reset 前为 clean
- [ ] squash 后只剩 1 个领先 commit
- [ ] `git push upstream HEAD --force-with-lease` 成功，无 `--force`
- [ ] `gh auth status` 显示已登录
- [ ] base 分支正确探测（main / master）
- [ ] `gh pr create` 返回 PR URL
- [ ] `gh pr merge --squash --delete-branch` 成功
- [ ] 步骤 5 输出含 PR URL + squash commit SHA + 改动文件清单
- [ ] 回报 closeout 表格含 PR URL + 文件列表 + 时间戳

## 7. 错误案例（高频坑）

| 错误操作                                            | 实际后果                                                                        | 正确做法                                                               |
| --------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| 不查领先数直接`git reset --soft upstream/master`  | n=0 时 soft reset 会把所有 working tree 改动塞进一个新 commit，可能误提交脏文件 | 先`git rev-list --count upstream/master..HEAD`，n=0 走普通 push 流程 |
| 软 reset 后用普通`git push upstream <branch>`     | non-fast-forward 被拒                                                           | 必须`--force-with-lease`                                             |
| 用`git push -f` 不用 with-lease                   | 覆盖远端，丢别人工作                                                            | 用`--force-with-lease`                                               |
| `--base` 写死成 `master`，但仓库实际是 `main` | PR 开到不存在的 base，报 422                                                    | 用步骤 4 的 BASE 自动探测逻辑                                          |
| `--base` 写死成 `main`，仓库是 `master`       | 同上                                                                            | 同上                                                                   |
| `gh pr merge` 用 `--merge` 或 `--rebase`      | 与流程要求的"squash 合并"不符                                                   | 统一`--squash --delete-branch`                                       |
| squash 后不删 head 分支                             | 远端留下垃圾分支                                                                | `--delete-branch`（squash 模式安全）                                 |
| 跳过步骤 5 直接 closeout                            | 用户看不到 PR 内容（commit 列表、文件改动）                                     | 必须跑`gh pr view --json ...`                                        |
| `--delete-branch` 在 rebase merge 模式也用        | squash 后安全，但 plain merge 模式下 head 分支可能仍有未合并 commit             | 本流程固定 squash，配套`--delete-branch` 安全                        |
| 401 Bad credentials 时反复重试                      | 浪费 token 配额，仍然失败                                                       | 立刻`gh auth status` 诊断，告知用户跑 `gh auth login`              |
| `gh pr create` 把 `--repo` 写成 origin 的 fork  | PR 提到自己的 fork，不是上游                                                    | 从`git remote get-url upstream` 解析                                 |
| `gh pr view --json merged`                        | `merged` 字段不存在，报 Unknown JSON field                                    | 用`mergedAt`（merged bool 看 `state=MERGED` 更直接）               |

## 8. 一句话速记

> **查领先数 → soft reset squash → push --force-with-lease → gh pr create → gh pr merge --squash --delete-branch → pr view 总结**
> force 必带 with-lease，base 自动探测，squash 不再问用户。
