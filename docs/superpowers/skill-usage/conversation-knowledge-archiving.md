# Conversation Knowledge Archiving

> **创建日期**: 2026-04-04
> **技能位置**: `~/.claude/skills/conversation-knowledge-archiving/SKILL.md`

## 概述

本项目使用 `conversation-knowledge-archiving` 技能将对话中的知识点归档到 `docs/` 目录。

## 核心原则

**扩展优于创建** — 除非新知识与现有文档完全无关，否则都应扩展现有文档。

## 触发条件

当出现以下情况时，应主动归档知识：

| 触发条件 | 示例 |
|----------|------|
| 完成重要任务或功能 | 完成 LocalNet 发现模块 |
| 做出重大决策 | "使用 UDP 多播而非 HTTP 广播做发现" |
| 建立架构模式 | 确立 LocalSend 风格的发现协议 |
| 解决复杂 bug | 发现多播地址映射问题的根本原因 |
| 用户明确要求 | 用户说 "保存这些知识" |
| 新工具/框架理解 | 理解 IP 多播协议的工作原理 |

## 归档流程

```
1. 识别对话核心知识点
        ↓
2. 在 docs/ 搜索现有相关文档
        ↓
3. 判断：扩展现有文档 OR 创建新文档
        ↓
4. 按照命名规范归档
        ↓
5. 更新版本历史（如果是扩展）
```

## 文档命名规范

| 类型 | 命名格式 | 示例 |
|------|----------|------|
| 架构文档 | `[模块名]-protocol-architecture.md` | `localnet-protocol-architecture.md` |
| 规格文档 | `YYYY-MM-DD-[模块名]-design.md` | `2026-04-04-localnet-design.md` |
| 计划文档 | `YYYY-MM-DD-[模块名]-plan.md` | `2026-04-04-localnet-mvp.md` |
| 协议文档 | `[协议名]-protocol.md` | `ip-multicast-protocol.md` |
| 技能使用 | `skill-usage/[技能名].md` | `skill-usage/conversation-knowledge-archiving.md` |

## 扩展现有文档的判断

| 情况 | 决策 | 示例 |
|------|------|------|
| 新知识与现有文档主题相关 | 扩展 | 在 `localnet-protocol-architecture.md` 中添加 HTTP 扫描细节 |
| 新知识是独立主题 | 新建 | `ip-multicast-protocol.md`（与 LocalNet 无关时） |
| 不确定时 | 先搜索 | 搜索确认后再决定 |

## 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.0 | 2026-04-04 | 初始版本，记录 conversation-knowledge-archiving 技能的创建和使用 |

## 相关文档

- `docs/localnet-protocol-architecture.md` — LocalNet 协议架构
- `docs/ip-multicast-protocol.md` — IP 多播协议详解
- `docs/superpowers/specs/2026-04-04-localnet-design.md` — LocalNet 设计规格
- `~/.claude/skills/conversation-knowledge-archiving/SKILL.md` — 技能源文件
