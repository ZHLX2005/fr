import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'const_set_tracker.dart';

/// 多巴胺风格圆环轨道绘制器
class SetTrackerRingPainter extends CustomPainter {
  final double cx;
  final double cy;
  final double radius;
  final double startAngle;
  final double sweepAngle;
  final int selectedIndex;
  final int themeCount;

  SetTrackerRingPainter({
    required this.cx,
    required this.cy,
    required this.radius,
    required this.startAngle,
    required this.sweepAngle,
    required this.selectedIndex,
    required this.themeCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(cx, cy);
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 底轨 - 柔和灰色
    final basePaint = Paint()
      ..color = const Color(0xFFE8E8EC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = SetTrackerConst.arcStrokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, basePaint);

    // 计算当前选中段的角度范围
    if (themeCount > 0) {
      final segmentSweep = sweepAngle / themeCount;
      final selectedStart = startAngle + segmentSweep * selectedIndex;

      // 选中段渐变高光
      final highlightPaint = Paint()
        ..shader = SweepGradient(
          startAngle: selectedStart - 0.05,
          endAngle: selectedStart + segmentSweep + 0.05,
          colors: [
            SetTrackerConst.themes[selectedIndex % SetTrackerConst.themes.length].gradient[0].withValues(alpha: 0.3),
            SetTrackerConst.themes[selectedIndex % SetTrackerConst.themes.length].gradient[0],
            SetTrackerConst.themes[selectedIndex % SetTrackerConst.themes.length].gradient[1],
            SetTrackerConst.themes[selectedIndex % SetTrackerConst.themes.length].gradient[0].withValues(alpha: 0.3),
          ],
          stops: const [0.0, 0.2, 0.8, 1.0],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = SetTrackerConst.arcHighlightWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(rect, selectedStart, segmentSweep, false, highlightPaint);

      // 两端圆点装饰 - 选中段
      final dotPaint = Paint()
        ..color = SetTrackerConst.themes[selectedIndex % SetTrackerConst.themes.length].gradient[0];

      for (final angle in [selectedStart, selectedStart + segmentSweep]) {
        final dx = cx + radius * math.cos(angle);
        final dy = cy + radius * math.sin(angle);
        canvas.drawCircle(Offset(dx, dy), 6, dotPaint);
      }
    }

    // 所有主题节点标记
    if (themeCount > 0) {
      final segmentSweep = sweepAngle / themeCount;
      for (int i = 0; i < themeCount; i++) {
        final angle = startAngle + segmentSweep * i + segmentSweep / 2;
        final dx = cx + radius * math.cos(angle);
        final dy = cy + radius * math.sin(angle);
        final isSelected = i == selectedIndex;

        // 外发光
        if (isSelected) {
          final glowPaint = Paint()
            ..color = SetTrackerConst.themes[i].gradient[0].withValues(alpha: 0.25)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(Offset(dx, dy), 14, glowPaint);
        }

        // 节点圆点
        final nodePaint = Paint()
          ..color = isSelected
              ? SetTrackerConst.themes[i].gradient[0]
              : const Color(0xFFCCCCD0)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(dx, dy), isSelected ? 8 : 5, nodePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SetTrackerRingPainter oldDelegate) =>
      cx != oldDelegate.cx ||
      cy != oldDelegate.cy ||
      radius != oldDelegate.radius ||
      selectedIndex != oldDelegate.selectedIndex;
}
