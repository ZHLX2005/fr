import 'package:flutter/material.dart';
import '../models/body_region.dart';

class BodyBlockPainter extends CustomPainter {
  final List<BlockRegion> regions;
  final String? highlightedId;
  static const double refW = 400.0;
  static const double refH = 800.0;

  BodyBlockPainter({required this.regions, this.highlightedId});

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / refW;
    final sy = size.height / refH;
    canvas.save();
    canvas.scale(sx, sy);

    for (final r in regions) {
      final isHit = r.id == highlightedId;
      final baseColor = tissueColors[r.tissue]!;
      final darkColor = tissueDarkColors[r.tissue]!;

      final fillPaint = Paint()
        ..color = isHit
            ? baseColor.withValues(alpha: 0.85)
            : baseColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = isHit ? darkColor : darkColor.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHit ? 3.0 : 1.5;

      switch (r.shape) {
        case BlockShape.circle:
          final center = Offset(r.x + r.w / 2, r.y + r.h / 2);
          canvas.drawCircle(center, r.w / 2, fillPaint);
          canvas.drawCircle(center, r.w / 2, borderPaint);
          break;
        case BlockShape.roundedRect:
        case BlockShape.stadium:
          final rr = RRect.fromRectAndRadius(
              r.rect, Radius.circular(r.radius));
          canvas.drawRRect(rr, fillPaint);
          canvas.drawRRect(rr, borderPaint);
          break;
        case BlockShape.rect:
          canvas.drawRect(r.rect, fillPaint);
          canvas.drawRect(r.rect, borderPaint);
          break;
      }

      // 标签
      final tp = TextPainter(
        text: TextSpan(
          text: r.label,
          style: TextStyle(
            color: Colors.white,
            fontSize: r.w < 40 ? 9 : 11,
            fontWeight: FontWeight.w600,
            shadows: const [
              Shadow(blurRadius: 2, color: Colors.black54),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: r.w - 4);

      tp.paint(canvas, Offset(
        r.x + (r.w - tp.width) / 2,
        r.y + (r.h - tp.height) / 2,
      ));

      // 有子图标记
      if (r.hasChildren) {
        final arrowTp = TextPainter(
          text: const TextSpan(
            text: '▸',
            style: TextStyle(color: Colors.white70, fontSize: 10),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        arrowTp.paint(canvas, Offset(r.x + r.w - 14, r.y + 2));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant BodyBlockPainter old) =>
      old.highlightedId != highlightedId;
}
