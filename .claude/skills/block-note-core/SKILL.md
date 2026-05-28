---
name: block-note-core
description: |
  当用户询问块编辑器、结构化笔记、Notion-like编辑器、
  笔记核心架构、Block模型、sealed class BlockType、
  RichText/Span/InlineFormat、笔记持久化、Demo页面实现、
  工具栏添加新工具、输入类型转换、Markdown导入、
  BlockWidgetStrategy、编辑器模式装饰、Enter行为策略、
  core目录结构、选中高亮行为时触发。
---

# Block Note Core — 结构化块树笔记编辑器

基于 `lib/core/note/` 的结构化笔记核心模型 + `lib/lab/demos/block_editor_demo/` 的 UI 实现。

```
SKILL.md (入口)
  ├── reference/types.md           # 数据模型层 — Block, BlockType 19子类, RichText, Span, InlineFormat
  ├── reference/persistence.md     # 持久化层 — NoteRepository CRUD + NoteFactory 门面
  └── reference/demo-ui.md         # UI 层 — EditorState, BlockCard, BlockWidgetStrategy, Toolbar, Panels
```

## 代码结构

```
lib/core/note/
├── factory.dart                     # NoteFactory 领域门面（创建所有服务 + tryConvert）
├── note_root_scope.dart             # InheritedWidget DI
├── core/
│   ├── core.dart                    # barrel
│   ├── block.dart                   # Block 不可变模型（sealed type + RichText content）
│   ├── block_codec.dart             # Block ↔ JSON 编解码
│   ├── text/                        # 富文本
│   │   ├── text.dart                # barrel
│   │   ├── rich_text.dart           # RichText (List<Span>)
│   │   ├── span.dart                # Span (text + InlineFormat?)
│   │   └── inline_format.dart       # InlineFormat sealed 7子类 + 编解码
│   ├── type/                        # BlockType 继承体系（sealed class + 19 part子类）
│   │   ├── type.dart                # sealed class BlockType 基类（onEnterType, multiline）
│   │   ├── type_registry.dart       # 反序列化工厂
│   │   ├── type_conversion_rule.dart   # TypeConversionRule<T> 输入触发转换规则
│   │   ├── type_conversion_registry.dart  # 注册表 + createDefault()
│   │   └── page/paragraph/heading/todo/code/... 各子类 part 文件
│   └── identity/                    # BlockId, BlockPath
├── persistence/
│   └── note_repository.dart         # 文件系统 CRUD（dir.listSync 避免 Windows 挂起）
├── widget/                          # Block widget 策略（O(1) Map 查找）
│   ├── widget.dart                  # barrel
│   ├── block_renderer.dart          # BlockRenderer 门面
│   ├── block_widget_factory.dart    # BlockWidgetFactory O(1) Map 策略分发
│   ├── block_widget_strategy.dart   # 策略接口（build + buildEditor）
│   ├── block_type_info.dart         # BlockTypeInfo
│   └── strategies/                  # 每类型一个策略文件
└── convert/
    └── md_to_block.dart             # Markdown → List<Block>
```

## 触发场景

- **Block 数据结构 / 新增 BlockType** → 读 `reference/types.md`
- **笔记保存/加载 / NoteFactory 架构** → 读 `reference/persistence.md`
- **Demo UI 架构 / 新增渲染策略** → 读 `reference/demo-ui.md`
- **工具栏添加新工具** → 读 `reference/demo-ui.md` Toolbar 章节
- **选中高亮 / Material 错误** → 读 `reference/demo-ui.md` BlockCard 章节
- **Markdown 导入** → 读 `reference/demo-ui.md` MD Import 章节
- **输入触发类型转换** → 读 `reference/demo-ui.md` Input Conversion 章节
- **文件结构 / 目录组织** → 回到本页代码结构
