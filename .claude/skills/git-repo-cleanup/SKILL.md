---
name: git-repo-cleanup
description: |
  清理git嵌套仓库，保持仓库隔离性，让 git add . 干净无污染。
  适用于 .claude/repo/ 或其他包含克隆仓库的目录。
  当用户提到"清理git"、"处理嵌套仓库"、"git隔离"、"保持干净"、
  "部分跟踪"、"白名单子目录"、"忽略但保留子目录"、"gitignore 否定规则"时触发。
---

# git-repo-cleanup 工作流程

## 问题背景

`.claude/repo/` 等目录包含通过 git clone 下载的嵌套仓库。这些仓库会被 git 检测为：
- 修改 (modified content)
- 嵌套 gitlink (作为子模块被跟踪)

导致 `git status` 不干净，`git add .` 会污染暂存区。

常见需求有两个层次：
- **完全忽略**：整个目录不跟踪
- **部分跟踪**：忽略目录下的克隆仓库，但跟踪一个"阅读笔记"子目录（如 `.claude/repo/_read/`）

---

## 模式 A：完全忽略（默认）

### 1. 检查当前状态

```bash
# 查看哪些嵌套仓库被跟踪
git ls-files --stage .claude/repo/

# 查看 git status
git status
```

### 2. 添加到 .gitignore

在项目 `.gitignore` 中添加规则：

```gitignore
# Cloned repositories (nested git repos)
.claude/repo/
```

### 3. 从 git 跟踪中移除

**如果是被跟踪的 gitlink (子模块)**：
```bash
git rm --cached -r .claude/repo/
```

**如果只是嵌套仓库（未被跟踪但有 modified content）**：
```bash
# 只需确保 .gitignore 生效
# 无需其他操作
```

### 4. 验证结果

```bash
# 确认暂存区干净
git status

# 提交更改
git add .gitignore
git commit -m "chore: ignore .claude/repo/ for cloned repos isolation"
```

**完成标准**：
- `git status` 显示 `nothing to commit, working tree clean`
- `git add .` 不会暂存 `.claude/repo/` 下的任何文件

---

## 模式 B：部分跟踪子目录（白名单）

适用场景：`.claude/repo/` 下保存了多个克隆仓库用于参考，但其中 `_read/` 子目录是阅读笔记或摘要，希望纳入版本控制。

### 1. .gitignore 正确表达

```gitignore
# Cloned repositories (nested git repos)
.claude/repo/*
!.claude/repo/_read/
!.claude/repo/_read/**
```

**三行的作用**：
- `.claude/repo/*` — 忽略目录下所有内容（注意是 `/*` 而非 `/`）
- `!.claude/repo/_read/` — 重新包含 `_read` 目录本身
- `!.claude/repo/_read/**` — 重新包含 `_read` 下的所有文件（含嵌套）

### 2. 验证规则生效

```bash
# 应该不被忽略
git check-ignore -v .claude/repo/_read
git check-ignore -v .claude/repo/_read/bbolt/README.md

# 应该被忽略
git check-ignore -v .claude/repo/agentscope
git check-ignore -v .claude/repo/agentscope/README.md
```

预期输出：
- `_read` 系列命中 `!.claude/repo/_read/` 或 `!.claude/repo/_read/**` 规则
- 其他子目录命中 `.claude/repo/*` 规则

### 3. 确认 .claude/repo 父目录本身可被发现

```bash
git check-ignore -v .claude/repo
# 预期：无输出（父目录不能被忽略，否则否定规则无法生效）
```

### 4. 提交更改

```bash
git add .gitignore
git add .claude/repo/_read/
git commit -m "chore: track .claude/repo/_read/ reading notes, ignore cloned repos"
```

---

## ⚠️ 高频错误案例

| 错误写法 | 实际后果 | 正确做法 |
|---------|---------|---------|
| `.claude/repo` + `!.claude/repo/_read` | 父目录被整体排除，否定规则**完全失效**，`_read` 仍被忽略 | 父级必须用 `.claude/repo/*`（带 `*`） |
| `.claude/repo/` + `!.claude/repo/_read/` | 同上，`/` 结尾仍然排除父目录本身 | 用 `.claude/repo/*` |
| 只有 `!.claude/repo/_read/` 一行否定 | 只能恢复目录本身，目录里的文件仍被忽略 | 必须再加 `!.claude/repo/_read/**` |
| `repo/` 宽泛规则 + `.claude/repo/*` | `repo/` 也会匹配 `.claude/repo` 作为目录 | 删掉冗余的 `repo/`，或改成 `repo/*` 并配合否定规则 |
| 否定规则写在忽略规则**之前** | 后面的忽略规则仍生效，否定不触发 | 否定规则必须放在忽略规则**之后** |

### 根因速记

> **Git 的硬规则**：如果父目录被排除，否定规则 `!` 无法在它下面重新包含任何东西。
> 父目录必须"半透明"——自身不被忽略，但内部内容被忽略。这就是 `dir/*` 模式的本质。

---

## 常见问题排查

| 现象 | 原因 | 解决 |
|------|------|------|
| `_read` 下的文件不出现在 `git status` | 父目录被整体排除 | 把 `.claude/repo` 改成 `.claude/repo/*` |
| `git check-ignore` 显示 `!.claude/repo/_read/**` 命中但文件仍不显示 | 父目录被排除，子文件无法浮上来 | 同上 |
| `git add .claude/repo/_read` 报错 `pathspec did not match` | 父目录不存在或被规则屏蔽 | 检查 `git check-ignore -v .claude/repo` 应无输出 |
| 部分子目录被跟踪了 | 否定规则位置错误或缺 `**` | 重新检查三行顺序与内容 |
| `git status` 看到 `modified content` | 嵌套仓库有改动 | 已在 .gitignore 中，提交 .gitignore 即可 |

---

## 验证清单

完成后必须满足：

- [ ] `git check-ignore -v .claude/repo` 无输出
- [ ] `git check-ignore -v .claude/repo/_read` 命中否定规则
- [ ] `git check-ignore -v .claude/repo/agentscope` 命中忽略规则
- [ ] `git status` 能看到 `.claude/repo/_read/` 下的新文件
- [ ] `git status` 看不到 `.claude/repo/agentscope/` 下的内容
- [ ] `git add .` 不会暂存任何克隆仓库内容
