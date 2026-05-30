# Chat Mode Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将底部工具栏改造为编辑/对话双模式切换，Factory 管理模式切换

**Architecture:** `ToolbarMode` 抽象基类定义接口，`BottomToolbarFactory` 注册式工厂管理 mode 实例。`EditorState` 持有 `_toolbarMode` 字符串状态。`block_editor_demo.dart` 的 `bottomNavigationBar` 委托 factory 构建。

**Tech Stack:** Flutter, Dart

---

### Task 1: 创建 toolbar_mode.dart（抽象基类 + Factory）

**Files:**
- Create: `lib/lab/demos/block_editor_demo/toolbar_mode.dart`

- [ ] **Step 1: 创建文件**

```dart
import 'package:flutter/material.dart';
import 'state.dart';

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

class BottomToolbarFactory {
  final _registry = <String, ToolbarMode>{};

  void register(ToolbarMode mode) {
    _registry[mode.name] = mode;
  }

  ToolbarMode? get(String name) => _registry[name];

  Widget build(String name, BuildContext context, EditorState editorState) {
    final mode = _registry[name];
    if (mode == null) return const SizedBox.shrink();
    return mode.build(
      context,
      editorState,
      onSwitchMode: () {
        final modes = _registry.keys.toList();
        final idx = modes.indexOf(name);
        if (idx < 0) return;
        final nextName = modes[(idx + 1) % modes.length];
        mode.onModeExit();
        editorState.switchTo(nextName);
        _registry[nextName]?.onModeEnter();
      },
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/lab/demos/block_editor_demo/toolbar_mode.dart
git commit -m "feat: add ToolbarMode abstract class and BottomToolbarFactory"
```

---

### Task 2: 创建 edit_toolbar.dart

**Files:**
- Create: `lib/lab/demos/block_editor_demo/edit_toolbar.dart`

- [ ] **Step 1: 创建文件**

从 `block_editor_demo.dart` 的 `_buildBottomToolbar()`（45-97 行）提取，实现 `ToolbarMode` 接口：

```dart
import 'package:flutter/material.dart';
import '../../../core/note/note_root_scope.dart';
import 'toolbar_mode.dart';
import 'state.dart';
import 'type_panel.dart';

class EditToolbar implements ToolbarMode {
  VoidCallback? onImportMdFile;
  VoidCallback? onImportMdText;

  void setImportCallbacks({VoidCallback? onImportMdFile, VoidCallback? onImportMdText}) {
    this.onImportMdFile = onImportMdFile;
    this.onImportMdText = onImportMdText;
  }

  @override
  String get name => 'edit';

  @override
  Widget build(BuildContext context, EditorState editorState, VoidCallback onSwitchMode) {
    return Container(
      color: Theme.of(context).canvasColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...NoteRootScope.of(context).noteRoot.availableTypes.map(
                        (info) => _toolbarTypeButton(context, editorState, info),
                      ),
                      const SizedBox(width: 8),
                      _toolbarButton(
                        label: '导入文件',
                        icon: Icons.description,
                        onTap: onImportMdFile ?? () {},
                      ),
                      _toolbarButton(
                        label: '导入文字',
                        icon: Icons.paste,
                        onTap: onImportMdText ?? () {},
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Material(
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => TypePanel.show(context, editorState),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Icon(Icons.expand_less, size: 22, color: Colors.grey[600]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbarTypeButton(BuildContext context, EditorState editorState, BlockTypeInfo info) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: info.label,
        child: Material(
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => editorState.addBlockWithType(info.prototype),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Icon(info.icon, size: 20, color: Colors.grey[600]),
            ),
          ),
        ),
      ),
    );
  }

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
}
```

**注意：** 导入文件/导入文字的 `onTap` 回调暂用空函数。这些功能需要 `EditorState` 暴露方法或由外部注入，待之后完善。

- [ ] **Step 2: 提交**

```bash
git add lib/lab/demos/block_editor_demo/edit_toolbar.dart
git commit -m "feat: create EditToolbar implementing ToolbarMode"
```

---

### Task 3: 创建 chat_bar.dart

**Files:**
- Create: `lib/lab/demos/block_editor_demo/chat_bar.dart`

- [ ] **Step 1: 创建文件**

```dart
import 'package:flutter/material.dart';
import 'toolbar_mode.dart';
import 'state.dart';

class ChatBar implements ToolbarMode {
  final _messages = <Map<String, dynamic>>[];
  final _controller = TextEditingController();
  Map<String, dynamic>? _pendingQuote;

  void setPendingQuote(Map<String, dynamic>? quote) {
    _pendingQuote = quote;
  }

  @override
  String get name => 'chat';

  @override
  void onModeEnter() {
    // 焦点自动聚焦输入框在 build 中处理
  }

  @override
  void onModeExit() {
    // 不清空 _messages 和 _controller，保留状态
  }

  @override
  Widget build(BuildContext context, EditorState editorState, VoidCallback onSwitchMode) {
    return Container(
      color: Theme.of(context).canvasColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Row(
            children: [
              // 退出按钮
              Material(
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onSwitchMode,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Icon(Icons.close, size: 20, color: Colors.grey[600]),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 引用预览
              if (_pendingQuote != null)
                Container(
                  constraints: const BoxConstraints(maxWidth: 80),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: Colors.blue[300]!, width: 2)),
                  ),
                  child: Text(
                    _extractQuoteText(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ),
              // 输入框
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLines: 1,
                  decoration: InputDecoration(
                    hintText: _pendingQuote != null ? '输入附加消息...' : '输入消息...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 4),
              // 发送按钮
              Material(
                borderRadius: BorderRadius.circular(20),
                color: Colors.blue.withValues(alpha: 0.1),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _sendMessage,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.send_rounded, size: 20, color: Colors.blue),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingQuote == null) return;
    _messages.add({
      if (text.isNotEmpty) 'content': text,
      if (_pendingQuote != null) 'quote': _pendingQuote,
    });
    _controller.clear();
    _pendingQuote = null;
    // 发送后保持 chat mode
  }

  String _extractQuoteText() {
    if (_pendingQuote == null) return '';
    final content = _pendingQuote!['content'] as Map<String, dynamic>?;
    if (content == null) return '';
    final spans = content['spans'] as List<dynamic>?;
    if (spans == null) return '';
    return spans
        .map((s) => (s as Map<String, dynamic>)['text'] as String? ?? '')
        .join();
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/lab/demos/block_editor_demo/chat_bar.dart
git commit -m "feat: create ChatBar implementing ToolbarMode"
```

---

### Task 4: 修改 state.dart —— 添加 mode 状态

**Files:**
- Modify: `lib/lab/demos/block_editor_demo/state.dart`

- [ ] **Step 1: 添加 mode 字段和方法**

在 `EditorState` 类中增加：

```dart
  String _toolbarMode = 'edit';

  void switchToChat() => switchTo('chat');
  void switchToEdit() => switchTo('edit');
  void switchTo(String mode) {
    _toolbarMode = mode;
    notifyListeners();
  }
  String get toolbarMode => _toolbarMode;
```

插入位置：在 `_noteId` 字段之后、`NoteFactory` 之前，或现有的 getter 区域。

- [ ] **Step 2: 提交**

```bash
git add lib/lab/demos/block_editor_demo/state.dart
git commit -m "feat: add toolbarMode state to EditorState"
```

---

### Task 5: 修改 block_editor_demo.dart —— 接入 Factory

**Files:**
- Modify: `lib/lab/demos/block_editor_demo/block_editor_demo.dart`

- [ ] **Step 1: 添加 import**

```dart
import 'toolbar_mode.dart';
import 'edit_toolbar.dart';
import 'chat_bar.dart';
```

- [ ] **Step 2: 添加 BottomToolbarFactory 字段和注册**

在 `_BlockEditorDemoState` 中添加。注意导入文件/文字的 `_importMdFile()` 和 `_showImportMdTextDialog()` 方法保留在 `_BlockEditorDemoState` 中（这些是该类的 UI 操作方法），导入按钮通过回调注入：

```dart
  late final BottomToolbarFactory _toolbarFactory = BottomToolbarFactory()
    ..register(EditToolbar()
      ..setImportCallbacks(
        onImportMdFile: _importMdFile,
        onImportMdText: _showImportMdTextDialog,
      ),
    )
    ..register(ChatBar());
```

插入位置：在 `_editorStateReady = true;` 赋值之后、`WidgetsBinding.instance.addPostFrameCallback` 之前。

注意：`_importMdFile` 和 `_showImportMdTextDialog` 不能是 `late` 字段初始化的一部分，因为此时 `context` 可能不可用。解决方案——将它们定义成方法，在 `didChangeDependencies` 中创建 factory，或在 `initState` 中延迟赋值。最简单：在 `_editorStateReady = true` 之后、`addPostFrameCallback` 之前，用 `WidgetsBinding.instance.addPostFrameCallback` 延迟创建 factory。_

**实际操作更简单：** 将 factory 创建移到 initState，然后在 didChangeDependencies 中注入回调：

```dart
@override
void initState() {
  super.initState();
  _toolbarFactory = BottomToolbarFactory()
    ..register(EditToolbar())
    ..register(ChatBar());
}

// 在 didChangeDependencies 中，_editorStateReady = true 之后：
_toolbarFactory
  .get('edit')
  ?.let((it) => (it as EditToolbar).setImportCallbacks(
    onImportMdFile: _importMdFile,
    onImportMdText: _showImportMdTextDialog,
  ));
```

- [ ] **Step 3: 替换 bottomNavigationBar**

将：

```dart
bottomNavigationBar: _buildBottomToolbar(),
```

改为：

```dart
bottomNavigationBar: _toolbarFactory.build(
  _editorState.toolbarMode,
  context,
  _editorState,
),
```

- [ ] **Step 4: 删除 _buildBottomToolbar 及其辅助方法**

删除 `_buildBottomToolbar()`、`_toolbarTypeButton()`、`_toolbarButton()` 方法（45-138 行）。

**保留：** `_importMdFile()` 和 `_showImportMdTextDialog()` 方法，因为它们已通过回调注入到 `EditToolbar` 中。

- [ ] **Step 5: 提交**

```bash
git add lib/lab/demos/block_editor_demo/block_editor_demo.dart
git commit -m "refactor: use BottomToolbarFactory for bottomNavigationBar"
```

---

### Task 6: 修改 card.dart —— space 触发切换到 chat mode

**Files:**
- Modify: `lib/lab/demos/block_editor_demo/card.dart`

- [ ] **Step 1: 修改硬键盘空格处理**

在 `_buildTextField` 的 `onKeyEvent` 中：

```dart
// 将：
if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space && _controller.text.isEmpty) {
  _showMessageDialog();
  return KeyEventResult.handled;
}
// 改为：
if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.space && _controller.text.isEmpty) {
  widget.editorState.switchToChat();
  return KeyEventResult.handled;
}
```

- [ ] **Step 2: 修改软键盘空格处理**

在 `onChanged` 中：

```dart
// 将：
if (value.length == 1 && (value == ' ' || value == ' ')) {
  _controller.text = '';
  _showMessageDialog();
  return;
}
// 改为：
if (value.length == 1 && (value == ' ' || value == ' ')) {
  _controller.text = '';
  widget.editorState.switchToChat();
  return;
}
```

- [ ] **Step 3: 修改引用操作的 context menu**

在 `_buildContextMenu` 中：

```dart
// 将：
onPressed: () {
  final selectedText = value.text.substring(
    value.selection.start,
    value.selection.end,
  );
  final noteRoot = NoteRootScope.of(context).noteRoot;
  final quotedBlock = noteRoot.createBlock(
    const ParagraphType(),
    content: RichText.text(selectedText),
    properties: {'originalBlockId': widget.block.id},
  );
  _showMessageDialog(quoteData: noteRoot.serializeBlock(quotedBlock));
},
// 改为：
onPressed: () {
  final selectedText = value.text.substring(
    value.selection.start,
    value.selection.end,
  );
  final noteRoot = NoteRootScope.of(context).noteRoot;
  final quotedBlock = noteRoot.createBlock(
    const ParagraphType(),
    content: RichText.text(selectedText),
    properties: {'originalBlockId': widget.block.id},
  );
  widget.editorState.switchToChat();
  // 引用由 ChatBar 内部处理，当前简化直接触发切换
  // 若需传递引用数据，需通过 _toolbarFactory.get('chat') as ChatBar 调用 setPendingQuote
},
```

- [ ] **Step 4: 提交**

```bash
git add lib/lab/demos/block_editor_demo/card.dart
git commit -m "feat: trigger chat mode on space instead of MessageDialog"
```

---

### Task 7: 编译验证

- [ ] **Step 1: 运行 flutter analyze**

```bash
cd /path/to/project && flutter analyze lib/lab/demos/block_editor_demo/
```

Expected: 无 error，可能少量 unused import warning

- [ ] **Step 2: 修复编译问题**

如果有 import 缺失或类型错误，修复它们。

- [ ] **Step 3: 清理 commmit**

```bash
git add -A
git commit -m "fix: resolve compilation issues after refactor"
```

---

### Task 8: 删除 message_dialog.dart（可选）

**Files:**
- Delete: `lib/lab/demos/block_editor_demo/message_dialog.dart`

- [ ] **Step 1: 确认无引用**

```bash
grep -r "message_dialog" lib/lab/demos/ --include="*.dart"
```

如果无结果则删除：

```bash
git rm lib/lab/demos/block_editor_demo/message_dialog.dart
git commit -m "cleanup: remove unused MessageDialog"
```
