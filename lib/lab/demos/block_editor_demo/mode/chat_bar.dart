import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'toolbar_mode.dart';
import '../state.dart';
import 'chat_message.dart';

class ChatBar implements ToolbarMode {
  final _messages = <ChatMessage>[];
  final _controller = TextEditingController();
  Map<String, dynamic>? _pendingQuote;
  VoidCallback? onStateChanged;

  void setPendingQuote(Map<String, dynamic>? quote) {
    _pendingQuote = quote;
  }

  @override
  String get name => 'chat';

  @override
  void onModeEnter() {
  }

  @override
  void onModeExit() {
  }

  @override
  Widget buildBody(BuildContext context, EditorState editorState, Widget body) {
    return ClipRect(
      child: Stack(
        children: [
          body,
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(color: Colors.transparent),
          ),
          if (_messages.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _ChatBubbleList(messages: _messages),
            ),
        ],
      ),
    );
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
    _messages.add(ChatMessage(content: text, isMe: true));
    _controller.clear();
    _pendingQuote = null;
    onStateChanged?.call();

    _mockReply();
  }

  void _mockReply() {
    Future.delayed(const Duration(seconds: 1), () {
      _messages.add(ChatMessage(content: '收到 ✅', isMe: false));
      onStateChanged?.call();
    });
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

class _ChatBubbleList extends StatelessWidget {
  final List<ChatMessage> messages;

  const _ChatBubbleList({required this.messages});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final msg = messages[messages.length - 1 - index];
          return _ChatBubble(message: msg);
        },
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isMe)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: CircleAvatar(
                radius: 12,
                child: Icon(Icons.person, size: 14),
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: message.isMe ? Colors.blue[500] : Colors.grey[100],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(message.isMe ? 16 : 4),
                  bottomRight: Radius.circular(message.isMe ? 4 : 16),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: message.isMe ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (message.isMe)
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}
