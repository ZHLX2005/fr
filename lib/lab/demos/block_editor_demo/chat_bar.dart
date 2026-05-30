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
