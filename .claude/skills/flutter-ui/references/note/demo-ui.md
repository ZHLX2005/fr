# UI Demo 层

来源：`lib/lab/demos/block_editor_demo/` + `lib/core/note/widget/`

## 目录结构

```
lib/lab/demos/block_editor_demo/
├── block_editor_demo.dart    # DemoPage 入口 + 底部 Toolbar
├── state.dart                # EditorState (ChangeNotifier)
├── card.dart                 # BlockCard 块卡片
├── note_panel.dart           # 笔记列表侧边栏
├── type_panel.dart           # 类型 + 工具操作面板
└── message_dialog.dart       # 消息 / 引用对话框

lib/core/note/widget/                          # 策略渲染体系
├── widget.dart                # barrel
├── block_renderer.dart        # BlockRenderer — 门面
├── block_widget_factory.dart  # BlockWidgetFactory — O(1) Map 策略查找
├── block_widget_strategy.dart # BlockWidgetStrategy — 策略接口
├── block_type_info.dart       # BlockTypeInfo 元信息
└── strategies/                # 每类型一个策略
    ├── strategies.dart        # barrel
    ├── paragraph_widget_strategy.dart
    ├── heading_widget_strategy.dart
    ├── todo_widget_strategy.dart
    ├── bullet_list_item_widget_strategy.dart
    ├── ordered_list_item_widget_strategy.dart
    ├── code_widget_strategy.dart
    ├── quote_widget_strategy.dart
    ├── callout_widget_strategy.dart
    ├── image_widget_strategy.dart
    ├── divider_widget_strategy.dart
    ├── page_widget_strategy.dart
    └── ...                    # 新增类型在此对应添加策略
```

---

## 渲染策略体系（核心架构）

```
Renderer 门面 → Factory O(1) Map → 各策略
BlockRenderer  → BlockWidgetFactory → BlockWidgetStrategy
```

三层职责明确：
- **BlockRenderer**：简单门面，接收 block 参数，转发给 factory
- **BlockWidgetFactory**：持有 `Map<String, BlockWidgetStrategy>`，按 `block.type.tag` O(1) 查找
- **BlockWidgetStrategy**：每个类型独立实现，负责 `build()` 和 `buildEditor()`

调用链：
```
NoteRootScope.of(context).noteRoot.renderBlock(block)
  → BlockRenderer.renderBlockContent(block)
    → BlockWidgetFactory.build(block)
      → strategies[block.type.tag].build(block, callbacks)
        → 返回该类型的 Widget
```

```
NoteRootScope.of(context).noteRoot.buildEditor(block, textField: ..., onToggleTodo: ...)
  → BlockRenderer.buildEditor(block, textField: ..., onToggleTodo: ...)
    → BlockWidgetFactory.buildEditor(block, callbacks, textField: textField)
      → strategies[block.type.tag].buildEditor(block, callbacks, textField: textField)
        → 返回包裹类型装饰的 Widget
```

---

## BlockWidgetStrategy — 策略接口

`lib/core/note/widget/block_widget_strategy.dart`

```dart
abstract class BlockWidgetStrategy {
  // 渲染态：构建只读 widget
  Widget build(Block block, BlockCallbacks callbacks);

  // 编辑态：将 [textField] 包裹上类型装饰
  Widget buildEditor(Block block, BlockCallbacks callbacks, {required Widget textField}) {
    return textField;  // 默认直接返回，子类可覆写
  }

  // UI 元信息（供工具栏消费）
  List<BlockTypeInfo> get typeInfoList;
}
```

```dart
class BlockCallbacks {
  final VoidCallback? onToggleTodo;
  final VoidCallback? onTapAddImage;
  const BlockCallbacks({this.onToggleTodo, this.onTapAddImage});
}
```

### 策略示例：OrderedListItemWidgetStrategy

```dart
class OrderedListItemWidgetStrategy extends BlockWidgetStrategy {
  @override
  List<BlockTypeInfo> get typeInfoList => const [
    BlockTypeInfo(prototype: OrderedListItemType(), icon: Icons.format_list_numbered, label: '1.', category: BlockTypeCategory.list),
  ];

  @override
  Widget build(Block block, BlockCallbacks callbacks) {
    final number = (block.type as OrderedListItemType).number;
    return Row(
      children: [
        Text('$number. ', style: const TextStyle(fontWeight: FontWeight.w500)),
        Expanded(child: Text(block.content.toPlainText())),
      ],
    );
  }

  @override
  Widget buildEditor(Block block, BlockCallbacks callbacks, {required Widget textField}) {
    final number = (block.type as OrderedListItemType).number;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('$number. ', style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
        Expanded(child: textField),
      ],
    );
  }
}
```

### 各策略的 buildEditor 装饰

| 策略 | 编辑装饰 |
|------|----------|
| ParagraphWidgetStrategy | 默认（无装饰） |
| HeadingWidgetStrategy | 默认（样式由 textStyleForType 处理） |
| PageWidgetStrategy | 默认（containerOnly，无编辑态） |
| **TodoWidgetStrategy** | Row：复选框 + Expanded(textField) |
| **BulletListItemWidgetStrategy** | Row：`•` 前缀 + Expanded(textField) |
| **OrderedListItemWidgetStrategy** | Row：`1.` 带编号前缀 + Expanded(textField) |
| **CodeWidgetStrategy** | Container：灰色背景 + 语言标签 + textField |
| **QuoteWidgetStrategy** | Row：3px 灰色左边框 + Expanded(textField) |
| **CalloutWidgetStrategy** | Container：蓝色背景 + 图标 + textField |
| DividerWidgetStrategy | containerOnly，无编辑态 |
| ImageWidgetStrategy | containerOnly，无编辑态 |

---

## 新增渲染策略步骤

1. 在 `strategies/` 新建 `your_type_widget_strategy.dart`
2. 实现 `BlockWidgetStrategy` — `build()` + 可选 `buildEditor()` + `typeInfoList`
3. 在 `strategies.dart` barrel 中添加 export
4. 在 `BlockWidgetBuilder`（`block_widget_builder.dart`）中注册：
   ```dart
   class BlockWidgetBuilder {
     Map<String, BlockWidgetStrategy> build() => {
       'paragraph': ParagraphWidgetStrategy(),
       'heading': HeadingWidgetStrategy(),
       'your_type': YourTypeWidgetStrategy(),  // ← 新增
       ...
     };
   }
   ```

实现 `BlockWidgetBuilder` 的文件路径与 `BlockWidgetFactory` 相邻。它负责构造策略 Map，传给 `BlockWidgetFactory` 构造函数。

---

## EditorState — 状态管理

`state.dart`，继承 `ChangeNotifier`。

### 核心状态

```dart
List<Block> _blocks;         // 扁平块列表
String? _selectedId;         // 选中块 ID
String? _noteId;             // 当前笔记 ID
Future<void>? _pendingSave;  // 待处理保存（串联防竞争）
```

### 方法一览

| 方法 | 说明 |
|------|------|
| `init()` | 加载最近笔记或新建空状态 |
| `switchNote(id)` | 替换 `_blocks` |
| `createNewNote()` | 清空 + 加一个空段落 + 立即保存 |
| `select(id)` | 设置 `_selectedId` |
| `clearSelection()` | 清空选中 |
| `toggleType(newType)` | 改当前块的 type |
| `deleteBlock()` | 删除当前块 + 选中相邻块 |
| `addBlock()` | 尾部加段落块 |
| `addBlockWithType(type)` | 在选中块后插入指定类型 |
| `updateContent(id, text)` | 文本输入 + 输入类型转换检查 |
| `updateImageSrc(id, src)` | 添加图片 |
| `toggleTodo(id)` | 切换 `TodoType.checked` |
| `moveBlock(old, new)` | 拖拽排序 |
| `importMd(source)` | 解析 markdown **插入到选中块后** |
| `deleteNote(id)` | 删除笔记文件 + 切换笔记 |

**统一模式**：`find → transform(copyWith) → notifyListeners() + _save()`

### 输入类型转换

`updateContent()` 中，仅 `ParagraphType` 时检查 `NoteFactory.tryConvert()`：

```dart
void updateContent(String id, String newText) {
  final idx = _blocks.indexWhere((b) => b.id == id);
  if (idx < 0) return;

  if (_blocks[idx].type is ParagraphType) {
    final result = _noteFactory.tryConvert(newText);
    if (result != null) {
      final (type, rest) = result;
      _blocks[idx] = _blocks[idx].copyWith(type: type, content: RichText.text(rest));
      notifyListeners();
      _save();
      return;
    }
  }

  _blocks[idx] = _blocks[idx].copyWith(content: RichText.text(newText));
  notifyListeners();
  _save();
}
```

---

## BlockCard — 块卡片

`card.dart`，`StatefulWidget`。

### 结构

```
┌────────────────────────────────────┐
│ [buildEditor 装饰]                  │
│  ┌─ 类型装饰 ──────────────────┐   │
│  │  TextField (选中时)          │   │
│  └─────────────────────────────┘   │
│ [buildEditor 装饰]                  │
└────────────────────────────────────┘
```

### 关键逻辑

- **选中与编辑**：`isSelected=true` → `buildEditor()` 包裹 `TextField`
- **非选中态**：`NoteRootScope.of(context).noteRoot.renderBlock(block, ...)` 渲染
- **容器类型**（`containerOnly = true` 如 PageType/ImageType/DividerType）跳过编辑态
- **自动聚焦**：`didUpdateWidget` 检测选中状态变化，`FocusNode.requestFocus()`

### 键盘事件（Focus.onKeyEvent）

硬件键盘事件统一在 `Focus.onKeyEvent` 中处理：

```dart
Focus(
  onKeyEvent: (node, event) {
    // 1. Backspace 删除空块
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace && _controller.text.isEmpty) {
      widget.editorState.deleteBlock();
      return KeyEventResult.handled;
    }
    // 2. Enter 创建新块（非 multiline 类型）
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && !ml) {
      final newType = widget.block.type.onEnterType;
      if (newType != null) widget.editorState.addBlockWithType(newType);
      return KeyEventResult.handled;
    }
    // 3. 空格（空块弹出消息对话框）
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space && _controller.text.isEmpty) {
      _showMessageDialog();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  },
  child: TextField(...)
)
```

> ⚠️ `Focus.onKeyEvent` 仅捕获硬件键盘事件。软键盘（IME）的 Enter 和 空格通过 `onChanged` 检测。

### onChanged 软键盘事件

```dart
onChanged: (value) {
  // 软键盘 Enter（非 multiline 类型）
  if (!ml && value.endsWith('\n')) {
    widget.editorState.updateContent(widget.block.id, value.trimRight());
    final newType = widget.block.type.onEnterType;
    if (newType != null) widget.editorState.addBlockWithType(newType);
    return;
  }
  // 软键盘空格触发对话框（空块时）
  if (value.length == 1 && (value == ' ' || value == ' ')) {
    _controller.text = '';
    _showMessageDialog();
    return;
  }
  widget.editorState.updateContent(widget.block.id, value);
},
```

### 关键边界处理

| 场景 | 处理方式 |
|------|----------|
| 硬件 Backspace 删空块 | `KeyDownEvent` 守卫，防止 `KeyUp` 二次触发 |
| 硬件 Enter 创建新块 | `onKeyEvent` + `!ml` 守卫 |
| 软键盘 Enter 创建新块 | `onChanged` 检测 `\n` 后缀 |
| 硬件空格（空块）→ 对话框 | `onKeyEvent space + text.isEmpty` |
| 软键盘空格（空块）→ 对话框 | `onChanged` 检测单字符空格 |
| 输入类型转换 | 仅 `ParagraphType` 调用 `tryConvert` |
| 多行块（CodeType） | `multiline=true` → `maxLines: null`，不处理 Enter |

---

## Context Menu — 文本选择引用

`_buildContextMenu()` 在系统上下文菜单末尾添加 "引用" 按钮。

```dart
Widget _buildContextMenu(BuildContext context, EditableTextState editableTextState) {
  final items = List<ContextMenuButtonItem>.from(editableTextState.contextMenuButtonItems);
  final value = editableTextState.textEditingValue;
  if (value.selection.isValid && !value.selection.isCollapsed) {
    items.add(ContextMenuButtonItem(
      label: '引用',
      onPressed: () {
        final selectedText = value.text.substring(value.selection.start, value.selection.end);
        final noteRoot = NoteRootScope.of(context).noteRoot;
        // 创建带 originalBlockId 的临时 Block
        final quotedBlock = noteRoot.createBlock(
          const ParagraphType(),
          content: RichText.text(selectedText),
          properties: {'originalBlockId': widget.block.id},
        );
        _showMessageDialog(quoteData: noteRoot.serializeBlock(quotedBlock));
      },
    ));
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: items,
  );
}
```

### 引用数据格式

**quoteData** 是完整的 Block 序列化 JSON，含 `properties.originalBlockId`：

```json
{
  "id": "<new-uuid>",
  "type": "paragraph",
  "content": {"spans": [{"text": "选中的文本", "format": null}]},
  "properties": {"originalBlockId": "<源 block 的 id>"}
}
```

`originalBlockId` 保留源 block ID，为未来 Agent 集成时定位源数据。

---

## MessageDialog — 消息 / 引用对话框

`message_dialog.dart`，底部弹出（`showModalBottomSheet`）。

### 触发方式

| 触发 | 条件 | 位置 |
|------|------|------|
| 硬件空格 | 空 block 选中 + 硬件键盘空格 | `Focus.onKeyEvent` |
| 软键盘空格 | 空 block 选中 + 软键盘空格 | `TextField.onChanged` |
| 文本选择"引用" | 选中文本 → 右键菜单 → 引用 | `contextMenuBuilder` |

### UI 结构

```
┌────────────────────────────────────┐
│    ───  (拖拽条)                    │
│  💬 发送消息              关闭      │
│  ─────────────────────────          │
│  ┌──────────────────────────┐      │
│  │ ║ 引用文本（灰色左边框）  │      │
│  └──────────────────────────┘      │
│  ┌──────────────────────┐          │
│  │      消息气泡         │ → 右对齐 │
│  └──────────────────────┘          │
│  ─────────────────────────          │
│  ┌─ 圆角输入框 ────┐ [➤]          │
│  └────────────────┘                │
└────────────────────────────────────┘
```

### 关键设计

- **引用只发送一次**：`_pendingQuote` 第一次发送后置 null，后续消息不携带
- **自动滚动**：发送后 `ScrollController.animateTo(maxScrollExtent)`
- **消息气泡**：蓝色背景、右对齐、最大宽度 75%
- **引用块**：灰色背景 + 蓝色左边框 + 最多 3 行溢出省略
- **键盘适配**：`margin: EdgeInsets.only(bottom: viewInsets.bottom)` 整体上移
- `showModalBottomSheet` 使用 `isScrollControlled: true` + `useSafeArea: true`

---

## Toolbar — 底部工具栏

`block_editor_demo.dart` 中 `_buildBottomToolbar()`。

### 当前按钮

水平滚动条内一行：

**类型插入区**（从 `NoteFactory.availableTypes` 动态生成）：
`P / H1(1) H2(2) H3(3) / ☐ / • / 1. / " / <> / — / 💡 / 🖼`

> 注意：H1/H2/H3 图标分别使用 `Icons.looks_one`/`looks_two`/`looks_3`，不再共用 `Icons.title`。

**导入工具**：
- `📄` 导入文件 (`_importMdFile`)
- `📋` 导入文字 (`_showImportMdTextDialog`)

**展开按钮**：`↓` 显示 TypePanel 全部类型

### `_proxyDecorator` — 拖拽预览

```dart
Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        ),
        child: child,
      );
    },
    child: child,
  );
}
```

### 底部空白添加块

`ReorderableListView.builder` 的 `itemCount = blocks.length + 1`，最后一项为空白点击区：

```dart
itemCount: blocks.length + 1,
onReorder: (oldIndex, newIndex) {
  if (oldIndex == blocks.length || newIndex == blocks.length) return;
  _editorState.moveBlock(oldIndex, newIndex);
},
itemBuilder: (context, index) {
  if (index == blocks.length) {
    return GestureDetector(
      key: const ValueKey('__add_block__'),
      onTap: () => _editorState.addBlock(),
      behavior: HitTestBehavior.translucent,
      child: const SizedBox(height: 60),
    );
  }
  return BlockCard(...);
},
```

### 添加新工具的三层模板

```
UI                           State                         模型
───────────────────────────────────────────────────────────────
_toolbarButton()         EditorState.doSomething()       Block/RichText...
  onTap → state.xxx()      find → copyWith
                            → notifyListeners + _save()
```

#### Step 1: State 层加方法

```dart
void doSomething(String id, /* 参数 */) {
  final idx = _blocks.indexWhere((b) => b.id == (id ?? _selectedId));
  if (idx < 0) return;
  _blocks[idx] = _blocks[idx].copyWith(/* 改 content / type / data */);
  notifyListeners();
  _save();
}
```

#### Step 2: UI 层加按钮

```dart
_toolbarButton(
  label: '工具名',
  icon: Icons.xxx,
  onTap: () => _editorState.doSomething(_editorState.selectedId),
),
```

`_toolbarButton` 通用实现：

```dart
Widget _toolbarButton({
  required String label,
  required IconData icon,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.only(right: 2),
    child: Material(
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Icon(icon, size: 20, color: Colors.grey[600]),
        ),
      ),
    ),
  );
}
```

---

## MD Import — Markdown 导入

### 文件职责

| 文件 | 职责 |
|------|------|
| `lib/core/note/convert/md_to_block.dart` | 纯函数，md 文本 → `List<Block>` |
| `state.dart` | `importMd()` 方法，解析后**插入到选中块之后** |
| `block_editor_demo.dart` | `_importMdFile()` 文件选取 + `_showImportMdTextDialog()` 文字导入 |
| `type_panel.dart` | 面板 "工具 → 导入 MD" 磁贴 |

### 调用流程

```
Toolbar (📄) → _importMdFile()
  → MediaService.pickFile(.md)
  → 读取文件内容
  → EditorState.importMd(source)
    → MdToBlock.parse(source)
    → 插入选中块后 / 追加文末 → notifyListeners → _save()

Toolbar (📋) → _showImportMdTextDialog()
  → showDialog 粘贴文本
  → EditorState.importMd(text)
```

### 插入模式

```dart
void importMd(String source) {
  final blocks = _noteFactory.parseMarkdown(source);
  if (blocks.isEmpty) return;

  if (_selectedId != null) {
    final idx = _blocks.indexWhere((b) => b.id == _selectedId);
    if (idx >= 0) {
      _blocks.insertAll(idx + 1, blocks);     // 插入到选中块后
      _selectedId = blocks.last.id;
      notifyListeners(); _save(); return;
    }
  }
  _blocks.addAll(blocks);                      // 无选中 → 追加文末
  _selectedId = blocks.last.id;
  notifyListeners(); _save();
}
```

### 支持语法

| Markdown | → BlockType | data |
|----------|-------------|------|
| `# ~ ###### 标题` | heading | level: 1-6 |
| `- 无序列表` | bulletListItem | — |
| `1. 有序列表` | orderedListItem | number: N |
| `- [x] 完成` | todo | checked: true |
| `- [ ] 待办` | todo | checked: false |
| `> 引用` | quote | — |
| `` ```lang `` | code | language: lang |
| `---` | divider | — |
| 其他 | paragraph | — |

内联格式暂存为纯文本。

---

## NotePanel

`note_panel.dart`，Scaffold endDrawer。
- 显示 `NoteFactory.listNotes()` 列表
- 点击切换笔记
- 新建笔记按钮
- `Dismissible` 滑动删除

### ⚠️ NotePanel 删除竞争

```dart
confirmDismiss: (_) async {
  ...
  if (confirmed == true) {
    setState(() => _notes.removeWhere((n) => n.id == note.id));  // 先同步移除
    await widget.editorState.deleteNote(note.id);                 // 再异步删除
    return true;
  }
}
```

必须**先同步移除列表项再 await**，否则 Dismissible 完整动画后 rebuild 会导致 "still part of tree" 错误。

### ⚠️ 异步安全

`NoteRootScope.of(context)` 必须在 `addPostFrameCallback` 中调用，因为 `InheritedWidget` 在 `initState()` 时不可用。

---

## TypePanel

`type_panel.dart`，底部弹出面板（`showModalBottomSheet`）。

结构：
- **标题**：H1 ~ H6
- **列表**：待办 / 无序列表 / 有序列表
- **文本**：段落 / 引用 / 代码 / 提示框
- **媒体**：图片 / 分割线
- **工具**：导入文件 / 导入文字（通过 `onImportMdFile`/`onImportMdText` 回调）

---

## 功能实现状态

| 功能 | 状态 | 位置 |
|------|:----:|------|
| Block 渲染（12种类型） | ✅ | `widget/strategies/` |
| Editor 模式装饰（6种类型） | ✅ | `buildEditor()` 在各策略 |
| BlockType 切换 | ✅ | `type_panel.dart` |
| 选中编辑 | ✅ | `card.dart` |
| Backspace 删除空块 | ✅ | `card.dart` — Focus.onKeyEvent KeyDown 守卫 |
| Enter 创建新块（硬件/软键盘） | ✅ | `Focus.onKeyEvent` + `onChanged` `\n` 检测 |
| 空格（空块）→ 消息对话框 | ✅ | 硬件: `onKeyEvent` / 软键盘: `onChanged` |
| 文本选择引用 | ✅ | `contextMenuBuilder` + originalBlockId |
| 消息对话框（底部弹出） | ✅ | `message_dialog.dart` |
| 输入触发类型转换 | ✅ | `TypeConversionRule` + `updateContent()` |
| 拖拽排序 | ✅ | ReorderableListView |
| Markdown 导入文件 + 文字 | ✅ | `md_to_block.dart` + insert-at-cursor |
| 笔记 CRUD | ✅ | `NoteRepository` + listSync |
| H1/H2/H3 独立图标 | ✅ | `Icons.looks_one`/`looks_two`/`looks_3` |
| 富文本 Span / 格式工具栏 | ❌ | — |
| 撤销/重做 | ❌ | — |
| Markdown 导出 | ❌ | — |
| AI 集成 | ❌ | — |

## 扩展方向（按优先级）

1. 富文本 Span 编辑器 + 格式工具栏（`InlineFormat` 已支持 7 种格式）
2. 撤销/重做
3. 补齐未实现 BlockType 渲染策略（toggle, embedCard, bookmark, equation, database, columnList, column, syncedBlock）
4. Markdown 导出
