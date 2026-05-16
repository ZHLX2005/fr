import 'package:flutter/material.dart';
import '../ai/note_ai_service.dart';

/// 对话消息模型
class ConversationMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'tool'
  final String content;
  final DateTime timestamp;
  final List<ToolCallInfo>? toolCalls;
  final String? toolCallId;

  ConversationMessage({
    required this.id,
    required this.role,
    this.content = '',
    DateTime? timestamp,
    this.toolCalls,
    this.toolCallId,
  }) : timestamp = timestamp ?? DateTime.now();

  const ConversationMessage._({
    required this.id,
    required this.role,
    this.content = '',
    required this.timestamp,
    this.toolCalls,
    this.toolCallId,
  });

  factory ConversationMessage.user(String content) =>
      ConversationMessage._(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: 'user',
        content: content,
        timestamp: DateTime.now(),
      );

  factory ConversationMessage.assistant(String content, {List<ToolCallInfo>? toolCalls}) =>
      ConversationMessage._(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: 'assistant',
        content: content,
        timestamp: DateTime.now(),
        toolCalls: toolCalls,
      );

  factory ConversationMessage.tool(String toolCallId, String content) =>
      ConversationMessage._(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        role: 'tool',
        content: content,
        timestamp: DateTime.now(),
        toolCallId: toolCallId,
      );
}

/// AI 对话面板
class AIConversationBar extends StatefulWidget {
  final List<ConversationMessage> messages;
  final bool isLoading;
  final String loadingStatus;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;
  final VoidCallback onClear;

  const AIConversationBar({
    super.key,
    required this.messages,
    required this.isLoading,
    this.loadingStatus = '正在思考…',
    required this.onSend,
    required this.onClose,
    required this.onClear,
  });

  @override
  State<AIConversationBar> createState() => _AIConversationBarState();
}

class _AIConversationBarState extends State<AIConversationBar> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  int _prevMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _prevMsgCount = widget.messages.length;
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AIConversationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != _prevMsgCount) {
      _prevMsgCount = widget.messages.length;
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isNotEmpty) {
      widget.onSend(text);
      _textController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFF8E1);

    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(isDark),
          const Divider(height: 1),
          Expanded(child: _buildMessageList(isDark)),
          if (widget.isLoading) _buildLoadingIndicator(isDark),
          _buildInputArea(isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(Icons.auto_awesome,
              size: 18,
              color: isDark ? const Color(0xFFFFCA28) : const Color(0xFFFFD54F)),
          const SizedBox(width: 8),
          Text('AI 对话',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[300] : Colors.grey[700])),
          const Spacer(),
          if (widget.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: '清空对话',
              onPressed: widget.onClear,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: '关闭',
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(bool isDark) {
    if (widget.messages.isEmpty) {
      return Center(
        child: Text('向 AI 发送消息开始对话',
            style: TextStyle(
                color: isDark ? Colors.grey[600] : Colors.grey[400],
                fontSize: 13)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) =>
          _buildMessageBubble(widget.messages[index], isDark),
    );
  }

  Widget _buildLoadingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(widget.loadingStatus,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[400] : Colors.grey[500])),
        ],
      ),
    );
  }

  Widget _buildInputArea(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF3D3D3D) : const Color(0xFFE0E0E0),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !widget.isLoading,
              style: TextStyle(
                  color: isDark
                      ? const Color(0xFFE0E0E0)
                      : const Color(0xFF2D2D2D)),
              decoration: InputDecoration(
                hintText: '输入消息…',
                hintStyle: TextStyle(
                    color:
                        isDark ? const Color(0xFF757575) : const Color(0xFF9E9E9E)),
                isDense: true,
                filled: true,
                fillColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onSubmitted: widget.isLoading ? null : (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: widget.isLoading ? null : _handleSend,
            icon: Icon(Icons.send_rounded,
                color:
                    isDark ? const Color(0xFFFFCA28) : const Color(0xFFFFD54F)),
            tooltip: '发送',
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ConversationMessage msg, bool isDark) {
    switch (msg.role) {
      case 'user':
        return _buildUserBubble(msg, isDark);
      case 'assistant':
        return _buildAssistantBubble(msg, isDark);
      case 'tool':
        return _buildToolBubble(msg, isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildUserBubble(ConversationMessage msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFE3F2FD),
                borderRadius:
                    BorderRadius.circular(12).copyWith(bottomRight: Radius.zero),
              ),
              child: Text(msg.content,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? const Color(0xFFE0E0E0)
                          : const Color(0xFF2D2D2D))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantBubble(ConversationMessage msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 8, top: 4),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFFFFCA28) : const Color(0xFFFFD54F),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.black87),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (msg.content.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3D3D3D) : Colors.white,
                      borderRadius: BorderRadius.circular(12)
                          .copyWith(bottomLeft: Radius.zero),
                      border: Border.all(
                          color: isDark
                              ? const Color(0xFF4D4D4D)
                              : const Color(0xFFE0E0E0),
                          width: 0.5),
                    ),
                    child: Text(msg.content,
                        style: TextStyle(
                            fontSize: 14,
                            color: isDark
                                ? const Color(0xFFE0E0E0)
                                : const Color(0xFF2D2D2D))),
                  ),
                if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: msg.content.isNotEmpty ? 4 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.build,
                              size: 14,
                              color: isDark ? Colors.grey[400] : Colors.grey[600]),
                          const SizedBox(width: 4),
                          Text('执行 ${msg.toolCalls!.length} 个操作',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600])),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBubble(ConversationMessage msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 32),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 14,
              color: isDark ? Colors.grey[500] : Colors.grey[400]),
          const SizedBox(width: 4),
          Flexible(
            child: Text(msg.content,
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey[500] : Colors.grey[400]),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
