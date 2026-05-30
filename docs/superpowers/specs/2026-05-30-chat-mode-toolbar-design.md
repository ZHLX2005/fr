# Chat Mode Toolbar Design

> 块编辑器对话框 UI 重构：将底部工具栏改造为编辑/对话双模式切换。

## 背景

当前 `block_editor_demo` 中，按空格弹出一个独立的 `MessageDialog` bottom sheet 用于发送消息。需要改为底部工具栏区域原位替换：编辑模式显示 block type 按钮，对话模式显示聊天输入框并接管 body（背景模糊 + 对话气泡）。

## 设计原则

- **Mode 自我描述**：每个 Mode 文件封装自己的完整 UI（工具栏 + body 装饰），宿主零判断
- **数据内聚**：消息列表属于 ChatBar，由 `onStateChanged` 回调通知重建
- **工厂负责生命周期**：`BottomToolbarFactory` 是 ChangeNotifier，`switchTo()` 统一控制 `onModeEnter/onModeExit`

## 文件架构

```
lib/lab/demos/block_editor_demo/
├── mode/
│   ├── toolbar_mode.dart          ← ToolbarMode 抽象基类
│   ├── toolbar_factory.dart       ← BottomToolbarFactory (ChangeNotifier)
│   ├── edit_toolbar.dart          ← 编辑模式
│   ├── chat_bar.dart              ← 对话模式（含消息状态 + 气泡渲染 + 背景模糊）
│   └── chat_message.dart          ← 消息数据类
├── block_editor_demo.dart         ← 宿主，body → factory.buildBody()
├── card.dart                      ← 空格 → editorState.switchToChat()
├── state.dart                     ← EditorState 持有 toolbarFactory，委托切换
└── ...
```

## ToolbarMode 抽象基类

```dart
abstract class ToolbarMode {
  String get name;

  /// 构建底部工具栏
  Widget build(BuildContext context, EditorState editorState, VoidCallback onSwitchMode);

  /// 装饰 body 区域。默认原样返回，需要接管 body（模糊、气泡等）时覆盖。
  Widget buildBody(BuildContext context, EditorState editorState, Widget body) => body;

  void onModeEnter() {}
  void onModeExit() {}
}
```

宿主统一调用 `buildBody`，不再 if/else。

## BottomToolbarFactory

- ChangeNotifier
- 构造函数内自注册 `EditToolbar()` 和 `ChatBar()`（ChatBar 注册前注入 `onStateChanged`）
- `switchTo(String)` 是唯一切换入口，内部调用 `onModeExit()` → 改 `_currentMode` → `onModeEnter()` → `notifyListeners()`
- `build()` / `buildBody()` 委托给当前 mode

```dart
class BottomToolbarFactory extends ChangeNotifier {
  final _registry = <String, ToolbarMode>{};
  String _currentMode = 'edit';

  BottomToolbarFactory() {
    final chat = ChatBar();
    chat.onStateChanged = notifyListeners;
    register(chat);
    register(EditToolbar());
  }

  void switchTo(String mode) {
    if (mode == _currentMode) return;
    _registry[_currentMode]?.onModeExit();
    _currentMode = mode;
    _registry[_currentMode]?.onModeEnter();
    notifyListeners();
  }

  Widget buildBody(BuildContext context, EditorState editorState, Widget body) {
    return _registry[_currentMode]?.buildBody(context, editorState, body) ?? body;
  }
}
```

## EditorState

持有 `toolbarFactory`，`switchToChat/switchToEdit` 委托给 factory。

```dart
class EditorState extends ChangeNotifier {
  final BottomToolbarFactory toolbarFactory;

  void switchToChat() => toolbarFactory.switchTo('chat');
  void switchToEdit() => toolbarFactory.switchTo('edit');

  EditorState({..., BottomToolbarFactory? toolbarFactory})
    : toolbarFactory = toolbarFactory ?? BottomToolbarFactory();
}
```

## block_editor_demo.dart

```dart
ListenableBuilder(
  listenable: Listenable.merge([_editorState, _editorState.toolbarFactory]),
  builder: (context, _) {
    return Scaffold(
      body: _editorState.toolbarFactory.buildBody(context, _editorState, normalBody),
      bottomNavigationBar: _editorState.toolbarFactory.build(context, _editorState),
    );
  },
)
```

## ChatBar 实现

### 底部工具栏

```
┌─────────────────────────────────────────────────┐
│ [X]  │  输入消息...                    │ [➤]    │
└─────────────────────────────────────────────────┘
```

### body 装饰

- 模糊层：BackdropFilter 覆盖原内容
- 气泡列表：显示在 body 底部、toolbar 上方

### 消息发送 + Mock 回复

```dart
void _sendMessage() {
  final text = _controller.text.trim();
  if (text.isEmpty && _pendingQuote == null) return;
  _messages.add(ChatMessage(content: text, isMe: true));
  _controller.clear();
  _pendingQuote = null;
  onStateChanged?.call();

  // mock 回复
  Future.delayed(const Duration(seconds: 1), () {
    _messages.add(ChatMessage(content: '收到 ✅', isMe: false));
    onStateChanged?.call();
  });
}
```

## ChatMessage 数据类

```dart
class ChatMessage {
  final String content;
  final bool isMe;
  final DateTime createdAt;
}
```

## 触发流

```
space (card.dart)
    → editorState.switchToChat()
    → toolbarFactory.switchTo('chat')
    → onModeExit('edit') → _currentMode='chat' → onModeEnter('chat')
    → notifyListeners()
    → body 重建（ChatBar.buildBody → 模糊 + 气泡）
    → bottomNavigationBar 重建（ChatBar.build → 输入框）

点击 X (ChatBar)
    → onSwitchMode()
    → toolbarFactory._switchToNext()
    → toolbarFactory.switchTo('edit')
    → onModeExit('chat') → _currentMode='edit' → onModeEnter('edit')
    → notifyListeners()
    → body 恢复原样
    → bottomNavigationBar 恢复编辑工具栏
```

## 要点总结

| 关注点 | 归属 |
|--------|------|
| 底部工具栏 | `mode.build()` — 每个 Mode 自己画 |
| 模糊 + 气泡 | `mode.buildBody()` — 每个 Mode 自己决定 body 装饰 |
| 消息列表 | ChatBar 内部持有，`onStateChanged` 通知重建 |
| Mode 切换 | Factory 统一入口，保证生命周期一致性 |
| 宿主 | 零判断，只做委托调用 |

## 后续迭代

- 持久化存储
- 真实网络回复
- 历史记录
- 引用 block 内容的完整预览
