part of 'main.dart';

/// 左上角聊天入口：💬 图标 + 最新一条消息预览（同一 pill 内，无动画）
///
/// 命名：区别于 chess_room_page.dart 的 _ChatFab（PlayerStrip 上的"详细历史"入口）
/// 形态：无预览 = 48×48 圆形（只有图标）；有预览 = 胶囊，图标右侧跟最新内容
/// （文字单行省略 / emoji 缩略图），超时由宿主清空 preview → 立即收回圆形。
/// 身份色点复用 F2 约定：蓝 = 我 / 橙 = 对方。
class _ChatPill extends StatefulWidget {
  final bool enabled;
  final ChatEvent? preview;
  final String myDeviceId;
  final EmojiBundle emojiBundle;
  final FileResolver? fileResolver;
  final VoidCallback onTap;

  const _ChatPill({
    required this.enabled,
    required this.preview,
    required this.myDeviceId,
    required this.emojiBundle,
    required this.fileResolver,
    required this.onTap,
  });

  @override
  State<_ChatPill> createState() => _ChatPillState();
}

class _ChatPillState extends State<_ChatPill> {
  bool _hover = false;
  bool _active = false;

  /// 预览主体：文字单行省略 / emoji 缩略图
  Widget _buildPreview(ChatEvent e, ColorScheme scheme) {
    if (e.isEmoji) {
      final entry = widget.emojiBundle.byId[e.emojiId ?? ''];
      return SizedBox(
        width: 22,
        height: 22,
        child: _EmojiImage(
          image: entry?.imageProvider(widget.fileResolver),
          id: e.emojiId ?? '',
        ),
      );
    }
    return Flexible(
      child: Text(
        e.text ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          color: scheme.onSurface,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = widget.preview;
    // scale: 1.0 → 1.05 (hover) → 0.95 (active)
    final scale = _active ? 0.95 : (_hover ? 1.05 : 1.0);
    final isMe = preview?.from == widget.myDeviceId;
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _active = false;
      }),
      child: Listener(
        onPointerDown: (_) {
          if (widget.enabled) setState(() => _active = true);
        },
        onPointerUp: (_) {
          if (mounted) setState(() => _active = false);
        },
        onPointerCancel: (_) {
          if (mounted) setState(() => _active = false);
        },
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Material(
            color: scheme.surface,
            // 无预览时 48×48 = 圆；有预览时撑成胶囊（同 radius 24 视觉一致）
            shape: const StadiumBorder(side: BorderSide(color: Color(0xFF1A1A1A))),
            elevation: _hover ? 3 : 2,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: widget.enabled ? widget.onTap : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // mock: 22×22 自定义 SVG 聊天气泡
                      // （区别于 Icons.chat_bubble_outline_rounded）
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CustomPaint(
                          painter: _ChatBubbleIconPainter(
                            color: const Color(0xFF1A1A1A)
                                .withValues(alpha: widget.enabled ? 1.0 : 0.4),
                          ),
                        ),
                      ),
                      if (preview != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFF2A6FDB)
                                : const Color(0xFFC2410C),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        _buildPreview(preview, scheme),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
