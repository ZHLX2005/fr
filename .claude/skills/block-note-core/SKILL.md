---
name: block-note-core
description: |
  当用户询问块编辑器、结构化笔记、Notion-like编辑器、
  笔记核心架构、Block模型、富文本Span、BlockData、
  笔记持久化、Demo页面实现、工具栏添加新工具、
  Markdown导入、core目录结构、选中高亮行为时触发。
---

# Block Note Core — 结构化块树笔记编辑器

基于 `lib/core/note/` 的结构化笔记核心模型 + `lib/lab/demos/block_editor_demo/` 的 UI 实现。

```
SKILL.md (入口)
  ├── reference/types.md          # 数据模型层 — Block, BlockType, RichText, Span...
  ├── reference/persistence.md    # 持久化层 — NoteRepository CRUD
  └── reference/demo-ui.md        # UI 层 — EditorState, BlockCard, Renderer, Toolbar, Panels
```

## 代码结构

```
lib/core/note/
├── note.dart                     # barrel
├── core/                         # 数据模型（是什么）
│   ├── models/                   # Block, BlockType, BlockData, FlatBlock
│   ├── text/                     # RichText, Span, InlineFormat
│   ├── identity/                 # BlockId, BlockPath
│   └── core.dart                 # barrel
├── persistence/                  # 持久化（怎么存）
│   └── note_repository.dart
└── convert/                      # 转换（从哪来）
    └── md_to_block.dart          # Markdown → List<Block>
```

## 触发场景

- **Block 数据结构** → 读 `reference/types.md`
- **笔记保存/加载** → 读 `reference/persistence.md`
- **Demo UI 架构** → 读 `reference/demo-ui.md`
- **工具栏添加新工具** → 读 `reference/demo-ui.md` Toolbar 章节
- **选中高亮 / Material 错误** → 读 `reference/demo-ui.md` BlockCard 章节
- **Markdown 导入** → 读 `reference/demo-ui.md` MD Import 章节
- **文件结构 / 目录组织** → 回到本页代码结构
