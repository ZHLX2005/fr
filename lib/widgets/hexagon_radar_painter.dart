import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 六边形数据项
class HexagonItem {
  String label;
  double value; // 0.0 - 1.0
  Color color;

  HexagonItem({required this.label, required this.value, required this.color});
}

/// 六边形雷达图Painter
class HexagonRadarPainter extends CustomPainter {
  final List<HexagonItem> items;
  final String? selectedLabel;

  HexagonRadarPainter({required this.items, this.selectedLabel});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 40;
    final sides = items.length;

    // 绘制背景网格层（渐变）
    _drawBackgroundLayers(canvas, center, radius);

    // 绘制网格线
    _drawGridLines(canvas, center, radius, sides);

    // 绘制数据区域（渐变填充）
    _drawDataArea(canvas, center, radius, sides);

    // 绘制顶点标签和数据点
    _drawLabelsAndPoints(canvas, center, radius, sides);
  }

  void _drawBackgroundLayers(Canvas canvas, Offset center, double radius) {
    // 绘制多层渐变背景
    for (int i = 5; i > 0; i--) {
      final layerRadius = radius * (i / 5);
      final path = _createHexagonPath(center, layerRadius, items.length);

      final gradient = RadialGradient(
        colors: [
          Colors.blue.withValues(alpha: 0.02 * i),
          Colors.purple.withValues(alpha: 0.02 * i),
        ],
      );

      final paint = Paint()
        ..shader = gradient.createShader(
          Rect.fromCircle(center: center, radius: layerRadius),
        )
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);
    }
  }

  void _drawGridLines(Canvas canvas, Offset center, double radius, int sides) {
    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 绘制同心六边形
    for (int i = 1; i <= 5; i++) {
      final layerRadius = radius * (i / 5);
      final path = _createHexagonPath(center, layerRadius, sides);
      canvas.drawPath(path, gridPaint);
    }

    // 绘制从中心到顶点的线
    for (int i = 0; i < sides; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final endPoint = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, endPoint, gridPaint);
    }
  }

  void _drawDataArea(Canvas canvas, Offset center, double radius, int sides) {
    if (items.isEmpty) return;

    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final value = items[i].value.clamp(0.0, 1.0);
      final point = Offset(
        center.dx + radius * value * math.cos(angle),
        center.dy + radius * value * math.sin(angle),
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    // 渐变填充
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.blue.withValues(alpha: 0.3),
        Colors.purple.withValues(alpha: 0.3),
        Colors.pink.withValues(alpha: 0.3),
      ],
    );

    final paint = Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      )
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);

    // 边框
    final borderPaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, borderPaint);
  }

  void _drawLabelsAndPoints(
    Canvas canvas,
    Offset center,
    double radius,
    int sides,
  ) {
    for (int i = 0; i < sides; i++) {
      final item = items[i];
      final angle = (math.pi / 3) * i - math.pi / 2;
      final value = item.value.clamp(0.0, 1.0);

      // 数据点
      final point = Offset(
        center.dx + radius * value * math.cos(angle),
        center.dy + radius * value * math.sin(angle),
      );

      // 绘制数据点和连线
      final isSelected = selectedLabel == item.label;

      // 连线
      final linePaint = Paint()
        ..color = item.color.withValues(alpha: 0.6)
        ..strokeWidth = isSelected ? 3 : 2
        ..style = PaintingStyle.stroke;

      final lineEnd = Offset(
        center.dx + radius * 1.2 * math.cos(angle),
        center.dy + radius * 1.2 * math.sin(angle),
      );

      canvas.drawLine(point, lineEnd, linePaint);

      // 数据点（渐变）
      final pointGradient = RadialGradient(
        colors: [item.color, item.color.withValues(alpha: 0.5)],
      );

      final pointPaint = Paint()
        ..shader = pointGradient.createShader(
          Rect.fromCircle(center: point, radius: isSelected ? 10 : 8),
        );

      canvas.drawCircle(point, isSelected ? 10 : 8, pointPaint);

      // 外圈
      final outerPaint = Paint()
        ..color = Colors.white
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(point, isSelected ? 10 : 8, outerPaint);

      // 标签
      final labelPoint = Offset(
        center.dx + radius * 1.3 * math.cos(angle),
        center.dy + radius * 1.3 * math.sin(angle),
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: item.label,
          style: TextStyle(
            color: isSelected ? item.color : Colors.black87,
            fontSize: isSelected ? 14 : 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final labelOffset = Offset(
        labelPoint.dx - textPainter.width / 2,
        labelPoint.dy - textPainter.height / 2,
      );

      // 标签背景
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: labelPoint,
          width: textPainter.width + 12,
          height: textPainter.height + 6,
        ),
        const Radius.circular(4),
      );

      final bgPaint = Paint()
        ..color = isSelected ? item.color.withValues(alpha: 0.15) : Colors.white;

      canvas.drawRRect(bgRect, bgPaint);

      textPainter.paint(canvas, labelOffset);

      // 绘制数值
      final valueTextPainter = TextPainter(
        text: TextSpan(
          text: '${(item.value * 100).toInt()}%',
          style: TextStyle(
            color: item.color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      valueTextPainter.layout();

      final valueOffset = Offset(
        point.dx - valueTextPainter.width / 2,
        point.dy - valueTextPainter.height / 2 - 18,
      );
      valueTextPainter.paint(canvas, valueOffset);
    }
  }

  Path _createHexagonPath(Offset center, double radius, int sides) {
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant HexagonRadarPainter oldDelegate) {
    return items != oldDelegate.items ||
        selectedLabel != oldDelegate.selectedLabel;
  }
}
