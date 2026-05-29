import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'const_set_tracker.dart';

/// 通用弧线轨道绘制器（支持上弧/下弧）
class ArcTrackPainter extends CustomPainter {
  final double cx;
  final double cy;
  final double radius;
  final double startAngle;
  final double sweepAngle;
  final int selectedIndex;
  final int itemCount;
  final Color highlightColor;

  ArcTrackPainter({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.startAngle,
    required this.sweepAngle,
    required this.selectedIndex,
    required this.itemCount,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(cx, cy);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 底轨
    final basePaint = Paint()
      ..color = SetTrackerConst.trackBaseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = SetTrackerConst.arcStrokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, basePaint);

    // 选中段渐变高光
    if (itemCount > 0) {
      final segmentSweep = sweepAngle / itemCount;
      final selectedStart = startAngle + segmentSweep * selectedIndex;

      final highlightPaint = Paint()
        ..shader = SweepGradient(
          startAngle: selectedStart - 0.05,
          endAngle: selectedStart + segmentSweep + 0.05,
          colors: [
            highlightColor.withValues(alpha: 0.3),
            highlightColor,
            highlightColor.withValues(alpha: 0.3),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = SetTrackerConst.arcHighlightWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, selectedStart, segmentSweep, false, highlightPaint);

      // 两端圆点装饰
      final dotPaint = Paint()..color = highlightColor;
      for (final angle in [selectedStart, selectedStart + segmentSweep]) {
        final dx = cx + radius * math.cos(angle);
        final dy = cy + radius * math.sin(angle);
        canvas.drawCircle(Offset(dx, dy), 5, dotPaint);
      }
    }

    // 所有节点标记
    if (itemCount > 0) {
      final segmentSweep = sweepAngle / itemCount;
      for (int i = 0; i < itemCount; i++) {
        final angle = startAngle + segmentSweep * i + segmentSweep / 2;
        final dx = cx + radius * math.cos(angle);
        final dy = cy + radius * math.sin(angle);
        final isSelected = i == selectedIndex;

        if (isSelected) {
          final glowPaint = Paint()
            ..color = highlightColor.withValues(alpha: 0.2)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(dx, dy), 12, glowPaint);
        }

        final nodePaint = Paint()
          ..color = isSelected ? highlightColor : const Color(0xFFCCCCD0)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(dx, dy), isSelected ? 6 : 4, nodePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant ArcTrackPainter oldDelegate) =>
      cx != oldDelegate.cx ||
      cy != oldDelegate.cy ||
      radius != oldDelegate.radius ||
      selectedIndex != oldDelegate.selectedIndex;
}
