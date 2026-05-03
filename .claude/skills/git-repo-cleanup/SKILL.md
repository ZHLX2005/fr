---
name: git-repo-cleanup
description: |
  清理git嵌套仓库，保持仓库隔离性，让 git add . 干净无污染。
  当用户提到"清理git"、"处理嵌套仓库"、"git隔离"、"保持干净"时触发。
  适用于 .claude/repo/ 或其他包含克隆仓库的目录。
---

# git-repo-cleanup 工作流程

## 问题背景

`.claude/repo/` 等目录包含通过 git clone 下载的嵌套仓库。这些仓库会被 git 检测为：
- 修改 (modified content)
- 嵌套 gitlink (作为子模块被跟踪)

导致 `git status` 不干净，`git add .` 会污染暂存区。

## 工作流程

### 1. 检查当前状态

```bash
# 查看哪些嵌套仓库被跟踪
git ls-files --stage .claude/repo/

# 查看 git status
git status
```

### 2. 添加到 .gitignore

在项目 `.gitignore` 中添加规则：

```bash
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

# 确认 .gitignore 生效
echo ".claude/repo/" >> .gitignore

# 提交更改
git add .gitignore
git commit -m "chore: ignore .claude/repo/ for cloned repos isolation"
```

## 验证标准

完成后应满足：
- `git status` 显示 `nothing to commit, working tree clean`
- `git add .` 不会暂存 `.claude/repo/` 下的任何文件

## 常见问题

| 问题 | 解决 |
|------|------|
| 嵌套仓库显示 "modified content" | 确保目录在 .gitignore 中 |
| gitlink 被跟踪 | `git rm --cached -r <path>` |
| 暂存区有删除记录 | `git reset HEAD <path>` |
| 无法提交 .gitignore | `git add .gitignore` 显式添加 |
