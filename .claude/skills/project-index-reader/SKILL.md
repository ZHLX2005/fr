---
name: project-index-reader
description: 当用户要求实现功能时，先从 .claude/repo/ 仓库中寻找相关案例。读取 PROJECT_INDEX.md 快速扫描，主题相关再深入源码。禁止立即编码。此 skill 仅适用于 .claude/repo/ 下的仓库。
version: 2.0.0
---
# Project Index Reader

## 核心原则

**先读索引，再找参考，后编码**。实现功能前必须先从现有仓库寻找相关案例。

在{项目仓库}/.claude/repo 寻找对应相关的源码 然后进行分析

## 工作流程

### Step 1: 扫描仓库索引

列出 `.claude/repo/` 下所有仓库的 `PROJECT_INDEX.md`，快速扫描：

- 项目名称
- 核心模块
- 功能描述

### Step 2: 读取相关索引

对筛选出的相关项目：

```
读取 .claude/repo/<项目名>/PROJECT_INDEX.md
可选读取 PROJECT_INDEX.json
```

### Step 3: 判断深入

| 情况                 | 操作             |
| -------------------- | ---------------- |
| 索引中有直接相关模块 | 深入读取相关源码 |
| 索引中无相关信息     | 跳过             |

### Step 4: 开始实现

只有在完成上述步骤后，才能开始编码。

## 寻找指令

扫描仓库列表：

```
Glob: */PROJECT_INDEX.md
```

查看索引内容：

```
Read: .claude/repo/<repo>/PROJECT_INDEX.md
Read: .claude/repo/<repo>/PROJECT_INDEX.json
```

搜索相关代码（如有索引不足）：

```
Grep: liquid glass | blur | backdrop | glassmorphism
Glob: **/*.dart
```

## 适用场景

✅ 实现功能时
✅ 学习参考时
✅ 寻找案例时

❌ 简单文件操作
❌ 用户已指定单个文件
