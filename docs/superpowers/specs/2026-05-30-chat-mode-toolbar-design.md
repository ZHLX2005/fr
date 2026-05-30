# Chat Mode Toolbar Design

> 块编辑器对话框 UI 重构：将底部工具栏改造为编辑/对话双模式切换。

## 背景

当前 `block_editor_demo` 中，按空格弹出一个独立的 `MessageDialog` bottom sheet 用于发送消息。需要改为底部工具栏区域原位替换：编辑模式显示 block type 按钮，对话模式显示聊天输入框。

## 文件架构

所有文件位于 `lib/lab/demos/block_editor_demo/` 统一文件夹下。

| 文件 | 操作 | 说明 |
|------|------|------|
| `toolbar_mode.dart` | 新增 | 抽象基类 `ToolbarMode` + `BottomToolbarFactory` |
| `edit_toolbar.dart` | 新增 | 编辑工具栏实现 |
| `chat_bar.dart` | 新增 | 聊天输入工具栏实现 |
| `state.dart` | 修改 | 增加 mode 切换状态 |
| `block_editor_demo.dart` | 修改 | `bottomNavigationBar` 改为 factory 构建，init 注册 mode |
| `card.dart` | 修改 | space 触发改为 `editorState.switchToChat()` |
| `message_dialog.dart` | 保留后删 | 验证 ChatBar 工作正常后再删除 |

## 类层次

### ToolbarMode（抽象基类）

```dart
abstract class ToolbarMode {
  String get name;
  Widget build(
    BuildContext context,
    EditorState editorState,
    VoidCallback onSwitchMode,
  );
  void onModeEnter() {}
  void onModeExit() {}
}
```

### BottomToolbarFactory

注册式工厂，管理 `ToolbarMode` 实例。`build()` 方法根据 name 查找已注册的 mode 并委托构建，注入 `onSwitchMode` 回调实现模式切换。

```dart
class BottomToolbarFactory {
  final _registry = <String, ToolbarMode>{};

  void register(ToolbarMode mode);
  ToolbarMode? get(String name);
  Widget build(String name, BuildContext context, EditorState editorState);
}
```

注册时机：`BlockEditorDemo.initState()` 或第一次 `didChangeDependencies` 中 one-time 注册。

### EditorState 新增 mode 状态

```dart
class EditorState extends ChangeNotifier {
  String _toolbarMode = 'edit';

  void switchToChat() { switchTo('chat'); }
  void switchToEdit() { switchTo('edit'); }
  void switchTo(String mode) { _toolbarMode = mode; notifyListeners(); }
  String get toolbarMode => _toolbarMode;
}
```

## 触发流

```
用户操作                        card.dart                     EditorState           bottomNavigationBar
───────                        ────────                      ───────────           ──────────────────
space (硬/软键盘)  ────────→   editorState.switchToChat() →   _toolbarMode='chat' → factory.build('chat')
                                                                                    ↓
                                                                                   ChatBar

点击 X 按钮  ────────────────→  onSwitchMode()  ───────────→  _toolbarMode='edit' → factory.build('edit')
                                                                                    ↓
                                                                                   EditToolbar
```

## EditToolbar 实现

从 `block_editor_demo.dart` 的 `_buildBottomToolbar()` 提取，保持原有布局不变：
- 水平滚动的 block type 按钮组
- expand_less 按钮（TypePanel 入口）
- 导入文件/文字按钮

## ChatBar 实现

底部工具栏原位替换，布局：

```
┌─────────────────────────────────────────────────┐
│ [X]  │  输入消息...                    │ [➤]    │
└─────────────────────────────────────────────────┘
```

- **X 按钮**：调用 `onSwitchMode` 切回编辑模式
- **输入框**：`TextField`，支持多行（maxLines: 4），回车发送
- **发送按钮**：发送消息后不清空消息历史，保持 ChatMode
- **内部状态**：`_messages` 列表、`_controller` 在 mode 切换时保留（`onModeExit` 不清空）

## card.dart 修改

### 硬键盘空格（_buildTextField 内）

```dart
if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space && _controller.text.isEmpty) {
  widget.editorState.switchToChat();
  return KeyEventResult.handled;
}
```

### 软键盘空格（onChanged）

```dart
if (value.length == 1 && (value == ' ' || value == ' ')) {
  _controller.text = '';
  widget.editorState.switchToChat();
  return;
}
```

### 引用操作（context menu）

引用功能不再触发 `MessageDialog`，改为切换到 ChatMode 并将引用数据暂存到 ChatBar：

```dart
// card.dart context menu "引用" 按钮
onPressed: () {
  final chatMode = _toolbarFactory.get('chat') as ChatBar;
  chatMode.setPendingQuote(quoteData);
  editorState.switchToChat();
}
```

`ChatBar` 需要暴露 `setPendingQuote(Map<String, dynamic>)` 方法，在 `build()` 中检查并显示引用预览。

## block_editor_demo.dart 修改

```dart
class _BlockEditorDemoState extends State<BlockEditorDemo> {
  late final BottomToolbarFactory _toolbarFactory = BottomToolbarFactory()
    ..register(EditToolbar())
    ..register(ChatBar());

  // ...

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ...
      bottomNavigationBar: _toolbarFactory.build(
        _editorState.toolbarMode,
        context,
        _editorState,
      ),
    );
  }
}
```

## message_dialog.dart 处置

`MessageDialog` 不再由 card.dart 直接调用。原有引用功能可在 ChatBar 中重新实现。建议：
1. 完成 ChatBar 重构并验证后删除 `message_dialog.dart`
2. 若引用功能需要保留，在 ChatBar 中提供 `setPendingQuote(Map<String, dynamic>)` 方法

## 未决事项（后续迭代）

- 对话消息的持久化存储
- 多轮对话历史展示
- 引用 block 内容的预览
