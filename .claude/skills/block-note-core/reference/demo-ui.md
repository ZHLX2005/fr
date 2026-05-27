# UI Demo 层

来源：`lib/lab/demos/block_editor_demo/` + `lib/core/note/widget/`

## 目录结构

```
lib/lab/demos/block_editor_demo/
├── block_editor_demo.dart    # DemoPage 入口 + 底部 Toolbar
├── state.dart                # EditorState (ChangeNotifier)
├── card.dart                 # BlockCard 块卡片
├── note_panel.dart           # 笔记列表侧边栏
└── type_panel.dart           # 类型 + 工具操作面板

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
| `importMd(source)` | 解析 markdown 替换当前笔记 |
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
- **Backspace 删除**：`Focus.onKeyEvent` 捕获 Backspace，空内容时调用 `deleteBlock()`
- **Enter 行为**：`onSubmitted` 捕获软键盘 Enter，调用 `addBlockWithType(block.type.onEnterType)`
- **容器类型**（`containerOnly = true` 如 PageType/ImageType/DividerType）跳过编辑态
- **自动聚焦**：`didUpdateWidget` 检测选中状态变化，`FocusNode.requestFocus()`

### 编辑态构建

```dart
Widget _buildTextField() {
  final ml = widget.block.type.multiline;
  final textField = Focus(
    onKeyEvent: (node, event) {
      if (event.logicalKey == LogicalKeyboardKey.backspace && _controller.text.isEmpty) {
        widget.editorState.deleteBlock();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: TextField(
      focusNode: _focusNode,
      controller: _controller,
      maxLines: ml ? null : 1,
      style: NoteRootScope.of(context).noteRoot.textStyleFor(widget.block) ?? ...,
      decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
      onChanged: (value) => widget.editorState.updateContent(widget.block.id, value),
      onSubmitted: ml ? null : (_) {
        final newType = widget.block.type.onEnterType;
        if (newType != null) widget.editorState.addBlockWithType(newType);
      },
    ),
  );
  return NoteRootScope.of(context).noteRoot.buildEditor(
    widget.block,
    textField: textField,
    onToggleTodo: () => widget.editorState.toggleTodo(widget.block.id),
  );
}
```

### ⚠️ Material 祖先问题

`ReorderableListView` 为每个 item 包裹 `LookupBoundary`，阻断 `TextField` 查找外部 `Material`。
解决方案：BlockCard 根节点包 `Material(type: MaterialType.transparency)`。

---

## Toolbar — 底部工具栏

`block_editor_demo.dart` 中 `_buildBottomToolbar()`。

### 当前按钮

水平滚动条内一行：

**类型插入区**（从 `NoteFactory.availableTypes` 动态生成）：
`P / H1 H2 H3 / ☐ / • / 1. / " / <> / — / 💡 / 🖼`

**导入 MD**：📄 导入 MD

**展开按钮**：↓ 显示 TypePanel 全部类型

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
| `state.dart` | `importMd()` 方法，解析后替换 `_blocks` |
| `block_editor_demo.dart` | `_importMdFile()` 文件选取 + 读取 + 导入 |
| `type_panel.dart` | 面板 "工具 → 导入 MD" 磁贴 |

### 调用流程

```
Toolbar (📄) / TypePanel → _importMdFile()
  → MediaService.pickFile(.md)
  → 读取文件内容
  → EditorState.importMd(source)
    → MdToBlock.parse(source)
    → 替换 _blocks → notifyListeners → _save()
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

## NotePanel / TypePanel

### NotePanel

`note_panel.dart`，Scaffold endDrawer。
- 显示 `NoteFactory.listNotes()` 列表
- 点击切换笔记
- 新建笔记按钮
- `Dismissible` 滑动删除
- **异步安全**：`NoteRootScope.of(context)` 包裹在 `addPostFrameCallback` 中

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

### TypePanel

`type_panel.dart`，底部弹出面板（`showModalBottomSheet`）。

结构：
- **标题**：H1 ~ H6
- **列表**：待办 / 无序列表 / 有序列表
- **文本**：段落 / 引用 / 代码 / 提示框
- **媒体**：图片 / 分割线
- **工具**：导入 MD（通过 `onImportMd` 回调）

---

## 功能实现状态

| 功能 | 状态 | 位置 |
|------|:----:|------|
| Block 渲染（12种类型） | ✅ | `widget/strategies/` |
| Editor 模式装饰（6种类型） | ✅ | `buildEditor()` 在各策略 |
| BlockType 切换 | ✅ | `type_panel.dart` |
| 选中编辑 | ✅ | `card.dart` |
| Backspace 删除空块 | ✅ | `card.dart` — Focus.onKeyEvent |
| Enter 创建新块（含类型策略） | ✅ | `BlockType.onEnterType` |
| 输入触发类型转换 | ✅ | `TypeConversionRule` + `updateContent()` |
| 拖拽排序 | ✅ | ReorderableListView |
| Markdown 导入 | ✅ | `md_to_block.dart` + state + toolbar + panel |
| 笔记 CRUD | ✅ | `NoteRepository` + listSync |
| 富文本 Span / 格式工具栏 | ❌ | — |
| 撤销/重做 | ❌ | — |
| Markdown 导出 | ❌ | — |
| AI 集成 | ❌ | — |

## 扩展方向（按优先级）

1. 富文本 Span 编辑器 + 格式工具栏（`InlineFormat` 已支持 7 种格式）
2. 撤销/重做
3. 补齐未实现 BlockType 渲染策略（toggle, embedCard, bookmark, equation, database, columnList, column, syncedBlock）
4. Markdown 导出
