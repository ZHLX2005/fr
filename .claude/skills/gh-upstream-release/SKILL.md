---
name: gh-upstream-release
description: |
  Fork 模式下，把当前分支推送到 `upstream` 远端并对 `master` 提 PR（可选 squash merge）的端到端 SOP。
  触发场景：用户说"用 gh 推送到 upstream"、"推到 upstream 然后 PR 到 master"、"用 gh 发版"、"同步到 upstream master"、"PR 到 master"、
  "发布当前分支"、"open PR against upstream"、明确给出 push + gh pr create 序列时。
  适用前提：本地有 `origin`（自己的 fork）和 `upstream`（canonical 仓库）两个 remote。
---

# gh-upstream-release

把"git push → gh pr create → 可选 squash merge"打包成可重复执行的 SOP。

## 0. 适用前提检查（必做）

```bash
git remote -v
```

预期：能同时看到 `origin`（fork）和 `upstream`（canonical）。
- 只有 `origin` → **不要继续**，用户可能尚未添加 upstream 远端，先 `git remote add upstream <url>`。
- 只有 `upstream`（没 fork）→ 这个 skill 不适用，**改用纯 `git push` 即可**。

## 1. 预检（推送前必跑）

```bash
git status                          # 必须 clean
git branch -vv                      # 确认当前分支和远端追踪关系
git log --oneline upstream/<branch>..HEAD    # 即将推送的提交列表
```

**若 `git status` 非 clean**：
- 有未提交改动 → 先 `git add` + `git commit`（或 `git stash`）
- 有未跟踪文件 → 确认不是误放进来的（如 `.env`、`.dart_tool/`），可加 `.gitignore`

**若当前分支不是目标分支**：
- `git checkout <branch>` 切到要推的分支（典型是 `joke` / feature 分支，**不是 master**）

## 2. 推送到 upstream

```bash
git push upstream <branch>
```

> **不要 `git push -f`**，除非用户明确说"force push"。

**失败诊断**：

| 报错 | 根因 | 修法 |
|---|---|---|
| `Permission denied (publickey)` | SSH key 未配到 GitHub | `ssh-add -l` 看 key 列表；重新 `gh auth login` 选 SSH |
| `Could not resolve host github.com` | 网络/代理问题 | 换 WiFi / 关代理 / 等几秒重试 |
| `rejected: non-fast-forward` | 远端有新提交 | `git fetch upstream <branch>` → rebase 或 merge 后再 push |
| `repository not found` | upstream URL 错或无权限 | `git remote -v` 检查，确认有 push 权限（fork 模式下需上游 maintainer 授权或走 PR） |

## 3. 用 gh 创建 PR

```bash
gh auth status                      # 先验证登录
gh pr create \
  --repo <upstream-org>/<repo> \
  --base master --head <branch> \
  --title "<PR 标题>" \
  --body  "<PR 正文>"
```

**参数推断规则**（按优先级）：

1. **`<upstream-org>/<repo>`** — 从 `git remote get-url upstream` 解析。例如 `git@github.com:ZHLX2005/fr.git` → `ZHLX2005/fr`
2. **`--base`** — 默认 `master`，但用户说"PR 到 main / develop"时用对应分支
3. **`--head`** — 当前分支名（`git branch --show-current`）
4. **`--title`** — 优先用用户给的话；未指定时用 `<branch> → master`（与用户最初请求格式一致）
5. **`--body`** — 默认简短一句"将 <branch> 合并到 <base>"，除非用户给了详细描述

**失败诊断**：

| 报错 | 根因 | 修法 |
|---|---|---|
| `HTTP 401: Bad credentials` | keyring 里的 gh token 失效 | `gh auth status` 确认 → 用户跑 `gh auth login`（不可自动化，阻塞） |
| `HTTP 422: Validation Failed` | 已有同 head→base 的 PR | `gh pr list --head <branch>` 查现有 PR URL 给用户 |
| `GraphQL: ... could not resolve to a Repository` | `--repo` 写错 | 从 `git remote get-url upstream` 重新解析 |
| `TLS handshake timeout` | 临时网络 | 等几秒重试；不行则 `gh pr create` 走 `--web` 让浏览器兜底 |

**`gh pr create --web` 兜底**：

如果 CLI 一直报错，**不要重试超过 1 次**。改用：
```bash
gh pr create --web --repo <org>/<repo> --base master --head <branch>
```
这会打开浏览器预填好表单，让用户手动点确认。

## 4. （可选）等 CI / 决定合并

PR 创建后，状态通常会有：

```bash
gh pr view <num> --repo <org>/<repo> --json number,state,mergeable,mergeStateStatus
```

`mergeStateStatus` 解读：
- `CLEAN` → 可直接合并
- `UNSTABLE` → CI 还在跑或部分非 success
- `BLOCKED` → 需要 review 通过
- `DIRTY` → 有冲突，必须先 rebase

**等 CI 还是直接合？** — **必须问用户**，不要替用户决定。用 AskUserQuestion 给两个明确选项：
- "立刻合并"
- "等 CI 跑完再合并"

**`gh pr checks <num>` 在 CI pending 时**会显示 `pending` 状态，这是正常的，**不要当成失败**。

## 5. 合并

```bash
# Merge commit（保留历史）
gh pr merge <num> --repo <org>/<repo> --merge

# Squash and merge（线性历史，PR 内多 commit 合一）
gh pr merge <num> --repo <org>/<repo> --squash --delete-branch

# Rebase and merge
gh pr merge <num> --repo <org>/<repo> --rebase
```

`--delete-branch` 会同时删远端 head 分支（**仅在 squash/rebase 后安全**，merge commit 模式慎用）。

## 6. 验证 + 回报

合并后给用户一个表格 closeout（按 `rules/claude-scholar-core.md` 的"任务完成摘要"格式）：

```markdown
📋 合并信息
| 项 | 值 |
|---|---|
| PR | https://github.com/<org>/<repo>/pull/<num> |
| 状态 | MERGED ✅ |
| 合并方式 | <merge/squash/rebase> |
| 合并者 | <gh user> |
| 合并时间 | <ISO timestamp> |
| Squash commit | <sha> "<headline> (#<num>)" |
| 删除/新增 | <X files, Y additions, Z deletions> |

📊 upstream master HEAD
<show 3 commits with `git log --oneline upstream/master -3`>

💡 Next Steps
1. 本地 master 同步：`git fetch upstream master` → `git pull --rebase upstream master`
2. 本地 head 分支清理：`git branch -d <branch>`（如远端已删）
3. CI 后置检查：关注 Actions 页面，确认合并后无回归
```

## 7. 验证清单

- [ ] `git remote -v` 看到 origin + upstream 两个 remote
- [ ] `git status` 推送前为 clean
- [ ] `git push upstream <branch>` 成功，无 force
- [ ] `gh auth status` 显示已登录
- [ ] `gh pr create` 返回 PR URL
- [ ] 合并决策**经用户确认**（不替用户选 squash/merge/rebase）
- [ ] 合并后本地 `git fetch upstream master` 同步
- [ ] 回报 closeout 表格含 PR URL + commit SHA + 时间戳

## 8. 错误案例（高频坑）

| 错误操作 | 实际后果 | 正确做法 |
|---|---|---|
| 第一次就跑 `git push upstream` 不查 status | 脏 tree 推送，可能带未提交改动 | 先 `git status`，clean 再推 |
| `gh pr create` 把 `--repo` 写成 `origin` 的 fork | PR 提到自己的 fork，不是上游 | 从 `git remote get-url upstream` 解析 |
| 401 Bad credentials 时反复重试 | 浪费 token 配额，仍然失败 | 立刻 `gh auth status` 诊断，告知用户跑 `gh auth login` |
| 不等 CI 直接 squash merge | CI 红灯但代码已进 master | 用 AskUserQuestion 问用户"等 CI / 立刻合" |
| `gh pr view --json merged` | `merged` 字段不存在，报 Unknown JSON field | 用 `gh pr view --json mergedAt`（merged 是 bool 状态，看 state=MERGED 更直接） |
| `--delete-branch` 在 merge commit 模式用 | 删了还有用 commit 引用历史的分支 | 仅在 squash/rebase 后用 `--delete-branch` |
| `git push -f upstream` 未确认 | 覆盖远端提交，可能丢别人工作 | 默认禁 force，必须用户明确同意 |
| `git push upstream master` | 把本地 master 推到 upstream master，绕过 PR | **永远不要直接 push 到目标 base 分支**，要 PR 流程 |
| `gh pr create` 不知道 head 分支名 | 默认 head 是当前分支，但若 detached HEAD 会失败 | `git branch --show-current` 显式指定 |
| CI pending 时误判为失败 | `gh pr checks` 报 pending 就停手 | pending ≠ failed，等 statusCheckRollup 全部 success |

## 9. 一句话速记

> **预检 → push → pr create → 问用户合不合 → 验证回报**
> 401 不重试，CI pending 不恐慌，force push 不擅自，merge 方式必问。
