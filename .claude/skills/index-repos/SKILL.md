---
name: index-repos
description: |
  使用 subagent 并行机制为多个仓库创建 PROJECT_INDEX.md 和 PROJECT_INDEX.json。
  当用户需要为多个独立仓库同时创建索引时自动触发。
  触发场景：
  - "为 .claude/repo 下所有仓库创建索引"
  - "并行执行 index skill"
  - "批量创建仓库索引"
  - /sc:index-repo 命令但有多个仓库
type: workflow
---
# 请加载/sc:index-repo这个skill !!!!!!!!!

处理{当前项目}/.claude/repo当中的项目,每个项目隔离

检查不存在PROJECT_INDEX.md 和 PROJECT_INDEX.json的仓库,对于没有index的仓库 进行并发   /sc:index-repo

# Index Repos - 多仓库并行索引创建

## 核心功能

使用 subagent 机制并行处理多个仓库的索引创建，每个仓库独立执行 `/sc:index-repo`。

## 执行流程

```
1. 识别需要创建索引的仓库列表
2. 为每个仓库并行启动 subagent
3. 各 subagent 独立调用 /sc:index-repo
4. 收集结果，验证索引文件生成
```

## Subagent 模板

```markdown
Agent({
  description: "Create index for {repo_name}",
  prompt: `
为 {repo_path} 仓库创建 PROJECT_INDEX.md 和 PROJECT_INDEX.json。

要求：
1. 读取 README.md 了解项目概述
2. 使用 Glob 分析目录结构
3. 识别核心模块和入口点
4. 生成简洁的索引文件（PROJECT_INDEX.md）
5. 同时生成 PROJECT_INDEX.json

输出到：{repo_path}/PROJECT_INDEX.md 和 .json
  `,
  subagent_type: "general-purpose",
  run_in_background: true
})
```

## 索引模板结构

```markdown
# Project Index: {project_name}

Generated: {timestamp}

## 📁 Project Structure
{major directories}

## 🚀 Entry Points
{key files}

## 📦 Core Modules
{module list}

## 🔗 Key Dependencies
{dependencies}

## 📝 Quick Start
{commands}
```

## 并行执行优势

| 串行执行             | 并行执行            |
| -------------------- | ------------------- |
| 5仓库 × 125s = 625s | 约 125s（最慢那个） |
| 顺序等待             | 同时完成            |
| 总耗时 N×T          | 总耗时 max(T)       |

## 经验总结

### ✓ 成功要点

1. 使用 `run_in_background: true` 实现真正并行
2. 每个 subagent 独立运行，互不依赖
3. 索引文件直接输出到对应仓库目录

### ⚠️ 错误教训

1. **跨会话历史不可用**：新会话无法访问之前 subagent 的具体输出
2. **耗时差异大**：大型仓库（如 eino）耗时约 125s，小型仓库约 60s
3. **结果保存**：关键输出应保存到共享位置供后续访问

## 输出文件

每个仓库生成两个文件：

- `{repo_path}/PROJECT_INDEX.md` - 人类可读
- `{repo_path}/PROJECT_INDEX.json` - 机器可读
