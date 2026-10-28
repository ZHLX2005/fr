part of 'main.dart';

/// 统一渲染 emoji 表情（KV 拉来的 imageProvider）。
///
/// 处理 imageProvider 为 null 的情况（EmojiEntry.imageProvider 在无 fileResolver
/// 且无本地缓存时返回 null —— board_chat_overlay.dart:38-44）。
class _EmojiImage extends StatelessWidget {
  final ImageProvider? image;
  final String id;
  const _EmojiImage({required this.image, required this.id});

  @override
  Widget build(BuildContext context) {
    final img = image;
    if (img == null) {
      // 兜底：emoji 加载不出来 → 显示浅灰占位 + id 前 2 字符（调试用）
      final hint = id.length >= 2 ? id.substring(0, 2) : '?';
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          hint,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Image(
      image: img,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.broken_image_outlined, size: 14),
      ),
    );
  }
}

/// FAB 聊天气泡 icon（mock 的 22×22 自定义 SVG）。
/// path data: M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z
/// （圆角矩形主体 + 左下小尾巴 — 与 Icons.chat_bubble_outline_rounded 不同）。
class _ChatBubbleIconPainter extends CustomPainter {
  final Color color;
  _ChatBubbleIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 24.0;
    final scaleY = size.height / 24.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0 / ((scaleX + scaleY) / 2)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final path = _buildBubblePath();
    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  /// 24x24 viewBox：圆角矩形 + 左下小尾巴
  Path _buildBubblePath() {
    final p = Path();
    // M21 15  : 起点右上偏左 (21, 15)
    p.moveTo(21, 15);
    // a2 2 0 0 1-2 2 : 弧到 (19, 17) 圆角
    p.arcToPoint(const Offset(19, 17), radius: const Radius.circular(2), clockwise: true);
    // H7 : 水平到 (7, 17)
    p.lineTo(7, 17);
    // l-4 4 : 相对位移 (-4, 4) → 画左下小尾巴到 (3, 21)
    p.lineTo(3, 21);
    // V5 : 垂直回到 (3, 5)
    p.lineTo(3, 5);
    // a2 2 0 0 1 2-2 : 弧到 (5, 3) 圆角
    p.arcToPoint(const Offset(5, 3), radius: const Radius.circular(2), clockwise: true);
    // h14 : 水平到 (19, 3)
    p.lineTo(19, 3);
    // a2 2 0 0 1 2 2 : 弧到 (21, 5) 圆角
    p.arcToPoint(const Offset(21, 5), radius: const Radius.circular(2), clockwise: true);
    // z : 闭合（回到 (21, 15)）
    p.close();
    return p;
  }

  @override
  bool shouldRepaint(covariant _ChatBubbleIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
