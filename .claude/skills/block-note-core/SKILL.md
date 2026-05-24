---
name: block-note-core
description: |
  当用户询问块编辑器、结构化笔记、Notion-like编辑器、
  笔记核心架构、Block模型、富文本Span、BlockData、
  笔记持久化、Demo页面实现、工具栏添加新工具时触发。
---

# Block Note Core — 结构化块树笔记编辑器

基于 `lib/core/note/` 的结构化笔记核心模型 + `lib/lab/demos/block_editor_demo/` 的 UI 实现。

```
SKILL.md (入口)
  ├── reference/types.md          # 数据模型层 — Block, BlockType, RichText, Span...
  ├── reference/persistence.md    # 持久化层 — NoteRepository CRUD
  └── reference/demo-ui.md        # UI 层 — EditorState, BlockCard, Renderer, Toolbar, Panels
```

## 三层结构

| 层 | 路径 | 指引 |
|---|------|------|
| **数据模型** | `lib/core/note/core/` | [→ types.md](reference/types.md) |
| **持久化** | `lib/core/note/persistence/` | [→ persistence.md](reference/persistence.md) |
| **UI Demo** | `lib/lab/demos/block_editor_demo/` | [→ demo-ui.md](reference/demo-ui.md) |

## 触发场景

- **Block 数据结构** → 读 `reference/types.md`
- **笔记保存/加载** → 读 `reference/persistence.md`
- **Demo UI 架构** → 读 `reference/demo-ui.md`
- **工具栏添加新工具** → 读 `reference/demo-ui.md` Toolbar 章节
- **选中高亮/Material 错误** → 读 `reference/demo-ui.md` BlockCard 章节
