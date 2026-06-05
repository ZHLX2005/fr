import 'package:flutter/material.dart';
import 'ai_models.dart';
import 'overlay/overlay_geometry.dart';
import 'overlay/overlay_manager.dart';

OverlayEntry? _currentOverlay;

/// 浮动对话窗口 — 可拖动、可缩放，点击"对话"按钮后弹出
class AiConversationOverlay {
  static void show(
    BuildContext context, {
    required BlockAIConversation conversation,
    String blockTitle = '',
  }) {
    _currentOverlay?.remove();

    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;

    const panelWidth = 340.0;
    const panelHeight = 480.0;
    final initialOffset = Offset(
      ((screenSize.width - panelWidth) / 2)
          .clamp(8, screenSize.width - panelWidth - 8),
      ((screenSize.height - panelHeight) / 2 - 20)
          .clamp(8, screenSize.height - panelHeight - 8),
    );

    final overlayEntry = OverlayEntry(
      builder: (ctx) => _AiConversationOverlayWidget(
        conversation: conversation,
        blockTitle: blockTitle,
        initialOffset: initialOffset,
        initialSize: const Size(panelWidth, panelHeight),
        onClose: () {
          _currentOverlay?.remove();
          _currentOverlay = null;
        },
      ),
    );

    _currentOverlay = overlayEntry;
    overlay.insert(overlayEntry);
  }

  static void dismiss() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}

class _AiConversationOverlayWidget extends StatefulWidget {
  final BlockAIConversation conversation;
  final String blockTitle;
  final Offset initialOffset;
  final Size initialSize;
  final VoidCallback onClose;

  const _AiConversationOverlayWidget({
    required this.conversation,
    required this.blockTitle,
    required this.initialOffset,
    required this.initialSize,
    required this.onClose,
  });

  @override
  State<_AiConversationOverlayWidget> createState() =>
      _AiConversationOverlayWidgetState();
}

class _AiConversationOverlayWidgetState
    extends State<_AiConversationOverlayWidget> {
  late TextEditingController _inputController;
  late ScrollController _scrollController;
  late OverlayManager _manager;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _manager = OverlayManager(
      geo: OverlayGeometry(
        position: widget.initialOffset,
        size: widget.initialSize,
      ),
    );
    _manager.addListener(_onGeometryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _manager.removeListener(_onGeometryChanged);
    _manager.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onGeometryChanged() {
    if (mounted) setState(() {});
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final msg = AIChatMessage.user(text);
    widget.conversation.addMessage(msg);
    _inputController.clear();
    setState(() {});

    widget.conversation.addMessage(AIChatMessage.loading());
    setState(() {});
    _scrollToBottom();

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      widget.conversation.removeLoading();
      widget.conversation.addMessage(AIChatMessage.ai('回复："$text"'));
      setState(() {});
      _scrollToBottom();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // 遮罩
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(color: Colors.black.withValues(alpha: 0.03)),
          ),
        ),
        // 窗口
        Positioned(
          left: _manager.geo.position.dx,
          top: _manager.geo.position.dy,
          child: Listener(
            onPointerDown: (e) =>
                _manager.handlePointerDown(e.localPosition, e.position),
            onPointerMove: (e) => _manager.handlePointerMove(e.position),
            onPointerUp: (e) => _manager.handlePointerUp(),
            onPointerCancel: (e) => _manager.handlePointerUp(),
            child: GestureDetector(
              onTap: () {},
              child: _buildPanel(context, colorScheme),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel(BuildContext context, ColorScheme colorScheme) {
    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        width: _manager.geo.size.width,
        height: _manager.geo.size.height,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context, colorScheme),
                Flexible(child: _buildBody(context, colorScheme)),
                _buildInputArea(context, colorScheme),
              ],
            ),
            // 右下角缩放把手
            Positioned(
              right: 4,
              bottom: 4,
              child: Icon(
                Icons.drag_handle,
                size: 16,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.forum, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            '对话',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: widget.onClose,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                child: Icon(Icons.close,
                    size: 16, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme) {
    final messages = widget.conversation.messages;

    return Container(
      padding: const EdgeInsets.all(14),
      child: messages.isEmpty
          ? Center(
              child: Text(
                '开始对话',
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              shrinkWrap: true,
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                if (msg.isLoading) {
                  return _buildLoadingBubble(colorScheme);
                }
                return _buildMessageBubble(context, colorScheme, msg);
              },
            ),
    );
  }

  Widget _buildMessageBubble(
      BuildContext context, ColorScheme colorScheme, AIChatMessage msg) {
    final isUser = msg.isUser;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 12, color: colorScheme.primary),
                    const SizedBox(width: 3),
                    Text('AI',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary)),
                  ],
                ),
              ),
            Container(
              constraints:
                  BoxConstraints(maxWidth: _manager.geo.size.width * 0.8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isUser
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                msg.content,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isUser
                      ? colorScheme.onPrimary
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBubble(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'AI 思考中...',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    maxLines: 3,
                    minLines: 1,
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: '使用 AI 处理各种任务...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 13,
                    icon:
                        const Icon(Icons.arrow_upward, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _footerBtn(context, Icons.attach_file, colorScheme),
              const SizedBox(width: 2),
              _footerBtn(context, Icons.palette, colorScheme),
              const Spacer(),
              Text(
                'Auto',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footerBtn(
      BuildContext context, IconData icon, ColorScheme colorScheme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {},
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
