import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'line_demo_models.dart';

// ═══════════════════════════════════════════════════════════════
// 绘制器
// ═══════════════════════════════════════════════════════════════

/// 游戏主绘制器：竖线 + 圆圈 + 判定线 + 炸开动画
class GamePainter extends CustomPainter {
  final List<List<FallingCircle>> columns;
  final List<ExplodeAnimation> explodes;
  final Color color;
  final double radius;
  final double screenWidth;
  final double screenHeight;
  final int columnCount;
  final double judgeY;

  GamePainter({
    required this.columns,
    required this.explodes,
    required this.color,
    required this.radius,
    required this.screenWidth,
    required this.screenHeight,
    required this.columnCount,
    required this.judgeY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final colWidth = w / columnCount;

    // ── 判定线 ──
    final judgePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, judgeY), Offset(w, judgeY), judgePaint);

    // ── 圆圈 ──
    final circlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    for (int i = 0; i < columns.length; i++) {
      final cx = colWidth * i + colWidth / 2;
      for (final circle in columns[i]) {
        if (circle.exploded) continue;

        double alpha = 0.3;
        // 穿过判定线后渐退
        if (circle.missed) {
          final dist = circle.currentY - judgeY;
          final fadeRange = screenHeight * 0.25;
          alpha = 0.3 * (1.0 - (dist / fadeRange).clamp(0.0, 1.0));
          if (alpha <= 0.01) continue;
        }

        circlePaint.color = color.withValues(alpha: alpha);

        if (circle.currentY >= -radius &&
            circle.currentY <= screenHeight + radius) {
          canvas.drawCircle(
              Offset(cx, circle.currentY), radius, circlePaint);
        }
      }
    }

    // ── 炸开动画 ──
    for (final explode in explodes) {
      _paintExplode(canvas, explode, w);
    }
  }

  void _paintExplode(Canvas canvas, ExplodeAnimation explode, double w) {
    final progress = explode.controller.value;
    final paint = Paint()..style = PaintingStyle.stroke;

    // Phase 1: 内爆缩小 (0.0 - 0.08)
    if (progress <= 0.08) {
      final t = progress / 0.08;
      final easedT = Curves.easeIn.transform(t);
      final currentRadius = explode.radius * (1.0 - easedT);

      if (currentRadius > 0.1) {
        paint.color = color.withValues(alpha: 0.3);
        paint.strokeWidth = 1.5;
        canvas.drawCircle(
            Offset(explode.x, explode.y), currentRadius, paint);
      }
    }

    // Phase 2: 粒子飞溅 (0.08 - 1.0)
    if (progress > 0.08) {
      final t = (progress - 0.08) / 0.92;
      final splashProgress = Curves.easeOut.transform(t);
      final fadeProgress = Curves.easeIn.transform(t);
      final particleSize = 10.0 * w / 750;

      for (final p in explode.particles) {
        final startX = explode.x + explode.radius * math.cos(p.angle);
        final startY = explode.y + explode.radius * math.sin(p.angle);
        final dx = math.cos(p.angle) * p.distance * splashProgress;
        final dy = math.sin(p.angle) * p.distance * splashProgress;
        final currentAlpha = p.initialAlpha * (1.0 - fadeProgress);

        if (currentAlpha > 0.01) {
          final particlePaint = Paint()
            ..color = color.withValues(alpha: currentAlpha)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(startX + dx, startY + dy),
              width: particleSize,
              height: particleSize,
            ),
            particlePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(GamePainter oldDelegate) => true;
}

/// 水退出动画绘制器
class WaterExitPainter extends CustomPainter {
  final double progress;
  final Color color;

  WaterExitPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;
    final midY = h / 2;
    final midX = w / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    const waveDepth = 8.0;

    // Phase 1: 上下涌入 (0.0 - 0.40)
    if (progress <= 0.40) {
      final t = progress / 0.40;
      final easedT = Curves.easeOutCubic.transform(t);

      final topFrontY = midY * easedT;
      final pathTop = Path();
      pathTop.moveTo(0, topFrontY);
      for (double x = 0; x <= w; x += 1) {
        final y = topFrontY +
            math.sin((x * 3 + progress * 1200) * math.pi / 180) * waveDepth;
        pathTop.lineTo(x, y);
      }
      pathTop.lineTo(w, 0);
      pathTop.lineTo(0, 0);
      pathTop.close();
      paint.color = color;
      canvas.drawPath(pathTop, paint);

      final bottomFrontY = h - midY * easedT;
      final pathBottom = Path();
      pathBottom.moveTo(0, bottomFrontY);
      for (double x = 0; x <= w; x += 1) {
        final y = bottomFrontY -
            math.sin((x * 3 + progress * 1200 + 60) * math.pi / 180) *
                waveDepth;
        pathBottom.lineTo(x, y);
      }
      pathBottom.lineTo(w, h);
      pathBottom.lineTo(0, h);
      pathBottom.close();
      paint.color = color;
      canvas.drawPath(pathBottom, paint);
    }

    // Phase 2: 两侧合拢 (0.40 - 0.80)
    if (progress > 0.40 && progress <= 0.80) {
      final t = (progress - 0.40) / 0.40;
      final easedT = Curves.easeInOutCubic.transform(t);

      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);

      final gapWidth = w * (1 - easedT);
      final gapLeft = midX - gapWidth / 2;
      const sideWaveDepth = 6.0;

      final pathLeft = Path();
      final leftEdge = gapLeft;
      pathLeft.moveTo(leftEdge, 0);
      for (double y = 0; y <= h; y += 1) {
        final x = leftEdge +
            math.sin((y * 3 + progress * 1500) * math.pi / 180) *
                sideWaveDepth;
        pathLeft.lineTo(x, y);
      }
      pathLeft.lineTo(0, h);
      pathLeft.lineTo(0, 0);
      pathLeft.close();
      paint.color = color;
      canvas.drawPath(pathLeft, paint);

      final pathRight = Path();
      final rightEdge = gapLeft + gapWidth;
      pathRight.moveTo(rightEdge, 0);
      for (double y = 0; y <= h; y += 1) {
        final x = rightEdge +
            math.sin((y * 3 + progress * 1500 + 60) * math.pi / 180) *
                sideWaveDepth;
        pathRight.lineTo(x, y);
      }
      pathRight.lineTo(w, h);
      pathRight.lineTo(w, 0);
      pathRight.close();
      paint.color = color;
      canvas.drawPath(pathRight, paint);
    }

    // Phase 3: 填满 (0.80 - 1.0)
    if (progress > 0.80) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
    }
  }

  @override
  bool shouldRepaint(WaterExitPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 线条风格 Slider 滑块 —— 极小实心圆点
class LineThumbShape extends SliderComponentShape {
  final double thumbRadius;

  const LineThumbShape({required this.thumbRadius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(thumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final paint = Paint()
      ..color = sliderTheme.thumbColor!
      ..style = PaintingStyle.fill;
    context.canvas.drawCircle(center, thumbRadius, paint);
  }
}
