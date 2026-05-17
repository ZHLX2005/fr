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

class _AIConversationBarState extends State<AIConversationBar>
    with SingleTickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  int _prevMsgCount = 0;
  late AnimationController _fadeCtrl;

  @override
  void initState() {
    super.initState();
    _prevMsgCount = widget.messages.length;
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AIConversationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != _prevMsgCount) {
      _prevMsgCount = widget.messages.length;
      _fadeCtrl.forward(from: 0);
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
    final cs = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: _fadeCtrl,
      child: Container(
        height: 320,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(cs),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            Expanded(child: _buildMessageList(cs)),
            if (widget.isLoading) _buildLoadingIndicator(cs),
            _buildInputArea(cs),
          ],
        ),
      ),
    );
  }

  // ──────────── 头部 ────────────

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI 助手',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
              Text('按住 Shift+Enter 换行',
                  style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface.withValues(alpha: 0.4))),
            ],
          ),
          const Spacer(),
          _headerBtn(Icons.delete_outline, '清空对话', widget.onClear,
              widget.messages.isEmpty, cs),
          const SizedBox(width: 4),
          _headerBtn(Icons.close, '关闭', widget.onClose, false, cs),
        ],
      ),
    );
  }

  Widget _headerBtn(IconData icon, String tip, VoidCallback onTap,
      bool disabled, ColorScheme cs) {
    return Opacity(
      opacity: disabled ? 0.3 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ),
      ),
    );
  }

  // ──────────── 消息列表 ────────────

  Widget _buildMessageList(ColorScheme cs) {
    if (widget.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 36,
                color: cs.onSurface.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text('输入消息开始对话',
                style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.35))),
            const SizedBox(height: 4),
            Text('可以问我任何问题…',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.25))),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) =>
          _buildMessageBubble(widget.messages[index], cs),
    );
  }

  // ──────────── 加载指示器 ────────────

  Widget _buildLoadingIndicator(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _TypingDots(color: cs.primary),
          const SizedBox(width: 8),
          Text(widget.loadingStatus,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
        ],
      ),
    );
  }

  // ──────────── 输入区 ────────────

  Widget _buildInputArea(ColorScheme cs) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
          color: cs.outlineVariant.withValues(alpha: 0.6), width: 0.5),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 1),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.5), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              enabled: !widget.isLoading,
              style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface),
              decoration: InputDecoration(
                hintText: '输入消息…',
                hintStyle: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withValues(alpha: 0.3)),
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerLowest,
                border: border,
                enabledBorder: border,
                focusedBorder: focusedBorder,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              onSubmitted: widget.isLoading ? null : (_) => _handleSend(),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: _textController.text.trim().isEmpty || widget.isLoading
                  ? cs.surfaceContainerHigh
                  : cs.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              onPressed: widget.isLoading || _textController.text.trim().isEmpty
                  ? null
                  : _handleSend,
              icon: Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: _textController.text.trim().isEmpty || widget.isLoading
                    ? cs.onSurface.withValues(alpha: 0.25)
                    : cs.onPrimary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: '发送',
            ),
          ),
        ],
      ),
    );
  }

  // ──────────── 消息气泡 ────────────

  Widget _buildMessageBubble(ConversationMessage msg, ColorScheme cs) {
    switch (msg.role) {
      case 'user':
        return _buildUserBubble(msg, cs);
      case 'assistant':
        return _buildAssistantBubble(msg, cs);
      case 'tool':
        return _buildToolBubble(msg, cs);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildUserBubble(ConversationMessage msg, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius:
                    BorderRadius.circular(14).copyWith(bottomRight: Radius.zero),
              ),
              child: Text(msg.content,
                  style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: cs.onPrimaryContainer)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantBubble(ConversationMessage msg, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 8, top: 4),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cs.primary, cs.primary.withValues(alpha: 0.7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome, size: 13, color: Colors.white),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (msg.content.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius:
                          BorderRadius.circular(14).copyWith(bottomLeft: Radius.zero),
                    ),
                    child: Text(msg.content,
                        style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: cs.onSurface)),
                  ),
                if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: msg.content.isNotEmpty ? 4 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.build_circle_outlined,
                              size: 13,
                              color: cs.onSurface.withValues(alpha: 0.45)),
                          const SizedBox(width: 4),
                          Text('执行 ${msg.toolCalls!.length} 个操作',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withValues(alpha: 0.45))),
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

  Widget _buildToolBubble(ConversationMessage msg, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, left: 36),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 13,
              color: cs.onSurface.withValues(alpha: 0.35)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(msg.content,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.35)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// 弹跳圆点打字指示器
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, _) {
              final t = (_ctrl.value * 3 + i) % 1.0;
              final scale = 1.0 + 0.6 * (t < 0.5 ? 2 * t : 2 * (1 - t));
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
