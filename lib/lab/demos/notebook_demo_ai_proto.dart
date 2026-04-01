import 'package:flutter/material.dart';
import '../lab_container.dart';

/// Notion AI 风格输入框原型
class NotebookDemoAiProto extends DemoPage {
  @override
  String get title => 'Notebook AI 原型';

  @override
  String get description => 'Notion AI 风格输入验证';

  @override
  Widget buildPage(BuildContext context) {
    return const MiniDocEditor();
  }
}

class MiniDocEditor extends StatefulWidget {
  const MiniDocEditor({super.key});

  @override
  State<MiniDocEditor> createState() => MiniDocEditorState();
}

class MiniDocEditorState extends State<MiniDocEditor> {
  final _textController = TextEditingController(text: '\n\n');
  final _textFocus = FocusNode();

  OverlayEntry? _aiEntry;
  final _aiController = TextEditingController();
  final _aiFocus = FocusNode();

  TextSelection? _savedSelection;

  bool get _aiOpen => _aiEntry != null;

  @override
  void dispose() {
    _textController.dispose();
    _textFocus.dispose();
    _aiController.dispose();
    _aiFocus.dispose();
    _removeAiOverlay();
    super.dispose();
  }

  void _triggerAiOverlay() {
    if (_aiEntry != null) return;

    _savedSelection = _textController.selection;
    _aiController.clear();

    _aiEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: Material(
          color: Colors.blue.shade50,
          elevation: 4,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 20, color: Colors.amber),
                  const SizedBox(width: 8),
                  const Text("AI:", style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AiPromptField(
                      controller: _aiController,
                      focusNode: _aiFocus,
                      onFirstChar: (ch) {
                        // 空字符（删除）会关闭
                      },
                      onCancel: _closeAiOverlay,
                      onSubmit: _submitAiText,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _closeAiOverlay,
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade200,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Overlay.of(context, rootOverlay: true).insert(_aiEntry!);
        _aiFocus.requestFocus();
      }
    });
  }

  void _closeAiOverlay() {
    _removeAiOverlay(restoreFocus: true);
  }

  void _submitAiText(String text) {
    if (text.isEmpty) {
      _closeAiOverlay();
      return;
    }

    final submittedText = '\n$text';
    final insertOffset = _savedSelection?.baseOffset ?? _textController.text.length;
    final currentText = _textController.text;

    // 在光标位置插入AI生成的文字
    final newText = currentText.substring(0, insertOffset) +
        submittedText +
        currentText.substring(insertOffset);

    _textController.text = newText;
    // 将光标移到插入文字之后
    _textController.selection = TextSelection.collapsed(
      offset: insertOffset + submittedText.length,
    );

    _closeAiOverlay();
  }

  void _removeAiOverlay({bool restoreFocus = false}) {
    _aiEntry?.remove();
    _aiEntry = null;

    if (restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _textFocus.requestFocus();
        if (_savedSelection != null) {
          _textController.selection = _savedSelection!;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _textFocus.requestFocus(),
      child: Container(
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Notion AI 风格输入原型',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _aiOpen ? null : _triggerAiOverlay,
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('触发 AI'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '点击"触发 AI"按钮打开输入框\n在输入框中输入内容后按回车关闭',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _textController,
                    focusNode: _textFocus,
                    maxLines: null,
                    style: TextStyle(
                      fontSize: 16,
                      color: theme.colorScheme.onSurface,
                      height: 1.6,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: '在此输入...',
                      hintStyle: TextStyle(color: theme.colorScheme.outline),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiPromptField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String ch) onFirstChar;
  final VoidCallback onCancel;
  final void Function(String text) onSubmit;

  const _AiPromptField({
    required this.controller,
    required this.focusNode,
    required this.onFirstChar,
    required this.onCancel,
    required this.onSubmit,
  });

  @override
  State<_AiPromptField> createState() => _AiPromptFieldState();
}

class _AiPromptFieldState extends State<_AiPromptField> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: true,
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: "输入指令后回车关闭...",
        contentPadding: EdgeInsets.zero,
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (text) => widget.onSubmit(text),
    );
  }
}

void registerNotebookDemoAiProto() {
  demoRegistry.register(NotebookDemoAiProto());
}
