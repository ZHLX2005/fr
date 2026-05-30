import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'toolbar_mode.dart';
import '../state.dart';
import 'chat_message.dart';
import 'tools/chat_tool.dart';
import 'tools/chat_tool_registry.dart';
import 'tools/translate_tool.dart';
import 'tools/summarize_tool.dart';
import 'tools/digest_tool.dart';
import 'tools/explain_tool.dart';

class ChatBar implements ToolbarMode {
  final _messages = <ChatMessage>[];
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _toolRegistry = ChatToolRegistry();
  Map<String, dynamic>? _pendingQuote;
  VoidCallback? onStateChanged;
  VoidCallback? _onSwitchMode;

  ChatBar() {
    _toolRegistry.register(TranslateTool());
    _toolRegistry.register(SummarizeTool());
    _toolRegistry.register(DigestTool());
    _toolRegistry.register(ExplainTool());
  }

  bool get _showToolPanel =>
      _controller.text.startsWith('/') && !_controller.text.contains(' ');

  String get _toolFilterQuery =>
      _showToolPanel ? _controller.text.substring(1) : '';

  void setPendingQuote(Map<String, dynamic>? quote) {
    _pendingQuote = quote;
  }

  @override
  String get name => 'chat';

  @override
  void onModeEnter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void onModeExit() {
    _focusNode.unfocus();
  }

  @override
  Widget buildBody(BuildContext context, EditorState editorState, Widget body) {
    return ClipRect(
      child: Stack(
        children: [
          body,
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 4),
            duration: const Duration(milliseconds: 200),
            builder: (context, sigma, child) {
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: Container(color: Colors.transparent),
              );
            },
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_messages.isNotEmpty)
                Flexible(
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: _ChatBubbleList(messages: _messages),
                  ),
                ),
              _buildInputBar(context),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return Container(
      color: Theme.of(context).canvasColor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_showToolPanel) _buildToolPanel(context),
              Row(
                children: [
                  Material(
                    borderRadius: BorderRadius.circular(6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _onSwitchMode?.call(),
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
                      focusNode: _focusNode,
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
                      onChanged: (_) => onStateChanged?.call(),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolPanel(BuildContext context) {
    final tools = _toolRegistry.filter(_toolFilterQuery);
    if (tools.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: tools.map((tool) => _buildToolItem(context, tool)).toList(),
      ),
    );
  }

  Widget _buildToolItem(BuildContext context, ChatTool tool) {
    return InkWell(
      onTap: () => _selectTool(tool),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(tool.icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Text(tool.label, style: const TextStyle(fontSize: 14)),
            if (tool.description != null) ...[
              const SizedBox(width: 8),
              Text(tool.description!, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
            ],
          ],
        ),
      ),
    );
  }

  void _selectTool(ChatTool tool) {
    _controller.text = '/${tool.label} ';
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _focusNode.requestFocus();
    onStateChanged?.call();
  }

  @override
  Widget build(BuildContext context, EditorState editorState, VoidCallback onSwitchMode) {
    _onSwitchMode = onSwitchMode;
    return const SizedBox.shrink();
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
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[messages.length - 1 - index];
        return _ChatBubble(message: msg);
      },
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
