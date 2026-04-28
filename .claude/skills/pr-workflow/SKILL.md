---
name: pr-workflow
description: PR管理工作流。当用户提到合并PR、查看PR、检查PR时使用此技能。
---

# PR Workflow Skill

## 查看所有Open PRs

```bash
gh pr list --repo ZHLX2005/fr --state open
```

## 查看PR详情

```bash
gh pr view <PR号> --repo ZHLX2005/fr
```

## 合并PR

使用 `--squash` 压缩合并：

```bash
gh pr merge <PR号> --repo ZHLX2005/fr --squash --delete-branch
```

## 查看其他用户的PR

```bash
gh pr list --repo <owner>/<repo> --state open
```

## 常见错误

- `--merge, --rebase, or --squash required` — 必须指定合并方式
- `auto-merge disabled` — 需要手动合并

## 工作流程

1. 列出所有 open PRs
2. 查看需要合并的 PR 详情
3. 执行 squash 合并并删除分支
