---
name: dev-git-flow
description: Git 工程流程层。覆盖三个子域：①PR 管理（合并 PR、查看 PR、检查 PR、gh pr list/view/merge --squash）②fork 上游发版（压缩领先 commit 成一个、squash 后推 upstream、gh pr create 端到端 SOP、force-with-lease、base 分支自动探测）③规范生成（阅读任意目录分析模块结构、生成防腐蚀规范 skill、不生成孤儿文档）。合并 PR、上游发版、为项目创建规范 skill 时加载本 skill。
---

# dev-git-flow — Git 工程流程层总入口

> 本页只做路由。每个子域是一份完整的原 skill 文档。

## 子域总览（先读这里）

| 子域 | 路由页 | 内容 | 何时进入 |
| --- | --- | --- | --- |
| PR 管理 | `references/pr/pr-workflow.md` | 单文档：gh pr list / view / merge --squash --delete-branch（ZHLX2005/fr 仓库） | 合并 PR / 查看 PR / 检查 PR |
| 上游发版 | `references/release/gh-upstream-release.md` | 单文档：6 步 SOP（查领先数 → soft reset squash → push --force-with-lease → gh pr create → squash merge → pr view 总结）+ 失败诊断表 | fork 模式压缩领先 commit 发版 / 推 upstream 开 PR |
| 规范生成 | `references/codegen/codebase-module-generator.md` | 单文档：读目录 → 依赖矩阵 → 代码异味 → 只生成 SKILL.md（不生成孤儿 md）+ 正反案例 | 为项目/模块创建防腐蚀规范 skill |

## 路径约定

- 子域文档在本层 `references/` 下按主题分目录，直接按上表路径读取。

## 跨子域规则（不进子域也要记住）

- **合并方式永远 `--squash --delete-branch`**（本项目惯例），必须显式指定，不能用默认 `--merge`。
- **force push 必带 `--with-lease`**，禁止裸 `--force`。
- 生成规范 skill 只产 `SKILL.md`，**禁止生成独立 .md 文档**（孤儿文档无人维护）。
- 提交遵循 Conventional Commits；只 add 本次任务产生的文件（与 flutter-biz 主工作流规范一致）。

## 协作 skill

- `key_board`：skill 生命周期管理（本层 codegen 产出的 skill 后续由它维护）
- `git-pushing` / `git-workflow`（全局 skill）：日常 commit/push 与分支协作
