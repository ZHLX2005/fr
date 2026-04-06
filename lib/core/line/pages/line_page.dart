import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/line_models.dart';

/// 游戏主绘制器：背景 + 血条 + 三种音符 + 炸开动画 + 判定文字
class GamePainter extends CustomPainter {
  final List<List<FallingNote>> columns;
  final List<ExplodeAnimation> explodes;
  final Color color;
  final double radius;
  final double screenWidth;
  final double screenHeight;
  final int columnCount;
  final double judgeY;
  final List<JudgeFeedback> judgeFeedbacks;
  final BackgroundStyle backgroundStyle;
  final double health; // 0.0 - 1.0
  final double dropDuration;
  final double scrollSpeed;
  final int gameElapsed; // 用于脉冲动画

  GamePainter({
    required this.columns,
    required this.explodes,
    required this.color,
    required this.radius,
    required this.screenWidth,
    required this.screenHeight,
    required this.columnCount,
    required this.judgeY,
    required this.judgeFeedbacks,
    required this.backgroundStyle,
    required this.health,
    required this.dropDuration,
    required this.scrollSpeed,
    required this.gameElapsed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final colWidth = w / columnCount;

    // 1. 背景
    if (backgroundStyle == BackgroundStyle.grid) {
      final gridPaint = Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      final spacing = 25.0 * screenWidth / 750;
      for (double x = spacing; x < w; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, screenHeight), gridPaint);
      }
      for (double y = spacing; y < screenHeight; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
      }
    } else if (backgroundStyle == BackgroundStyle.lines) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      for (int i = 0; i < columnCount; i++) {
        final cx = colWidth * i + colWidth / 2;
        canvas.drawLine(Offset(cx, 0), Offset(cx, screenHeight), linePaint);
      }
    }

    // 2. 血条
    _paintHealthBar(canvas, w);

    // 3. 判定线
    final judgePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, judgeY), Offset(w, judgeY), judgePaint);

    // 4. 音符
    for (int i = 0; i < columns.length; i++) {
      final cx = colWidth * i + colWidth / 2;
      for (final note in columns[i]) {
        if (note.event.type == NoteType.tap) {
          _paintTapNote(canvas, cx, note);
        } else if (note.event.type == NoteType.hold) {
          _paintHoldNote(canvas, cx, note);
        } else if (note.event.type == NoteType.slide) {
          _paintSlideNote(canvas, cx, note);
        }
      }
    }

    // 5. 炸开动画
    for (final explode in explodes) {
      _paintExplode(canvas, explode, w);
    }

    // 6. 判定文字反馈
    for (final fb in judgeFeedbacks) {
      final progress = fb.controller.value;
      final alpha = fb.baseAlpha * (1.0 - progress);
      if (alpha <= 0.01) continue;

      final textSpan = TextSpan(
        text: fb.text,
        style: TextStyle(
          fontSize: 10 * screenWidth / 750,
          fontWeight: FontWeight.w300,
          color: fb.color.withValues(alpha: alpha),
          letterSpacing: 2,
        ),
      );
      final tp = TextPainter(
        text: TextSpan(children: [textSpan]),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.layout(maxWidth: screenWidth);
      tp.paint(canvas, Offset(fb.x - tp.width / 2, fb.y - tp.height / 2));
      tp.dispose();
    }
  }

  void _paintHealthBar(Canvas canvas, double w) {
    final barWidth = 1.0;
    final barX = w - 12 - barWidth / 2;
    final dotTop = 120.0;
    final barHeight = 100.0;

    // 顶部圆点
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(barX, dotTop), 3.0, dotPaint);

    // 细线背景（固定100px）
    final lineBgPaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = barWidth;
    canvas.drawLine(Offset(barX, dotTop + 4), Offset(barX, dotTop + 4 + barHeight), lineBgPaint);

    // 细线填充（从底部向上）
    final fillHeight = barHeight * health.clamp(0.0, 1.0);
    if (fillHeight > 0) {
      final lineFillPaint = Paint()
        ..color = color.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = barWidth;
      canvas.drawLine(
        Offset(barX, dotTop + 4 + barHeight),
        Offset(barX, dotTop + 4 + barHeight - fillHeight),
        lineFillPaint,
      );
    }
  }

  void _paintTapNote(Canvas canvas, double cx, FallingNote note) {
    if (note.judged || note.removeMe) return;
    if (note.currentY < -radius || note.currentY > screenHeight + radius) return;

    double alpha = 0.3;
    if (note.currentY > judgeY) {
      final dist = note.currentY - judgeY;
      final fadeRange = screenHeight * 0.25;
      alpha = 0.3 * (1.0 - (dist / fadeRange).clamp(0.0, 1.0));
      if (alpha <= 0.01) return;
    }

    final circlePaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(Offset(cx, note.currentY), radius, circlePaint);
  }

  void _paintHoldNote(Canvas canvas, double cx, FallingNote note) {
  if (note.currentY < -radius * 2) return;

  final headY = note.currentY;

  // tail 在 head 上方（Y 值更小）
  final travelPerMsActual = screenHeight * scrollSpeed / dropDuration;
  final tailOffset = travelPerMsActual * note.event.holdDuration!;
  final tailY = headY - tailOffset;

  // 条宽度
  final barWidth = radius * 1.6;

  // 填充高度计算
  final totalHeight = headY - tailY;
  final fillBottom = headY;
  final fillTop = tailY + totalHeight * (1 - note.holdProgress);

  // 透明度计算
  double alpha;
  if (note.holdFadeOut > 0) {
    // 闪烁 alpha
    final flickerFreq = 30.0;
    final flicker = 0.5 + 0.5 * math.sin(note.holdFadeOut * math.pi * flickerFreq);
    alpha = 0.5 * (1.0 - note.holdFadeOut) * flicker;
  } else if (note.holding) {
    // 按住中：从 0.5 线性减小到 0
    alpha = 0.5 * (1.0 - note.holdProgress * 0.8);
  } else {
    alpha = 0.5;
  }
  if (alpha < 0.01) return;

  // ── 未填充区域（轮廓）──
  final outlinePaint = Paint()
    ..color = color.withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  canvas.drawRect(
    Rect.fromLTWH(cx - barWidth / 2, tailY, barWidth, totalHeight),
    outlinePaint,
  );

  // ── 填充区域（按住中才绘制）──
  if (note.holding || note.holdProgress > 0) {
    // 霓虹发光
    final glowAlpha = alpha * 0.6;
    final glowBlur = 15.0 * note.holdProgress;

    // 发光层（shadow）
    final glowPaint = Paint()
      ..color = color.withValues(alpha: glowAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);
    canvas.drawRect(
      Rect.fromLTWH(cx - barWidth / 2, fillTop, barWidth, fillBottom - fillTop),
      glowPaint,
    );

    // 实心填充
    final fillPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx - barWidth / 2, fillTop, barWidth, fillBottom - fillTop),
      fillPaint,
    );

    // 左边缘高光线
    final edgePaint = Paint()
      ..color = Color.lerp(color, Colors.white, 0.4)!.withValues(alpha: (0.6 + 0.3 * note.holdProgress) * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(cx - barWidth / 2, fillTop),
      Offset(cx - barWidth / 2, fillBottom),
      edgePaint,
    );

    // 顶部前沿亮条
    if (note.holdProgress > 0 && note.holdProgress < 1) {
      final edgeAlpha = alpha * (0.7 + 0.3 * note.holdProgress);
      final frontPaint = Paint()
        ..color = Colors.white.withValues(alpha: edgeAlpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(cx - barWidth / 2, fillTop - 1.5, barWidth, 3),
        frontPaint,
      );
    }
  }

  // ── 头部圆圈 ──
  final circlePaint = Paint()
    ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  canvas.drawCircle(Offset(cx, headY), radius, circlePaint);

  // ── 粒子爆发（完成时）──
  if (note.holdFadeOut > 0) {
    _paintHoldNoteParticles(canvas, cx, headY, alpha, note.holdFadeOut);
  }
}

void _paintHoldNoteParticles(Canvas canvas, double cx, double headY, double alpha, double fadeOut) {
  if (fadeOut <= 0) return;

  // 闪烁效果：alpha 在基础值 ±20% 范围内震荡，频率随 fadeOut 加快
  final flickerFreq = 30.0; // Hz
  final flicker = 0.8 + 0.2 * math.sin(fadeOut * math.pi * flickerFreq);
  final flickerAlpha = alpha * flicker * (1.0 - fadeOut);
  if (flickerAlpha < 0.01) return;

  // 粒子：8 个，从头部爆发
  // 使用一个固定种子确保粒子方向稳定
  final particleCount = 8;
  for (int i = 0; i < particleCount; i++) {
    final baseAngle = (2 * math.pi * i / particleCount);
    final speed = 40.0 + (i % 3) * 10.0; // 40-60 px/s
    final vx = math.cos(baseAngle) * speed * (1 - fadeOut * 0.5);
    final vy = math.sin(baseAngle) * speed * (1 - fadeOut * 0.5) - 20 * fadeOut; // 向上偏移
    final px = cx + vx * fadeOut * 0.3;
    final py = headY + vy * fadeOut * 0.3;
    final particleAlpha = (1 - fadeOut) * 0.8;
    final particleSize = 2.0 + (i % 2) * 1.5;

    if (particleAlpha > 0.01) {
      final pPaint = Paint()
        ..color = Color.lerp(color, Colors.white, 0.3)!.withValues(alpha: particleAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), particleSize * (1 - fadeOut * 0.3), pPaint);
    }
  }
}

  void _paintSlideNote(Canvas canvas, double cx, FallingNote note) {
    if (note.judged || note.removeMe) return;
    if (note.currentY < -radius || note.currentY > screenHeight + radius) return;

    final circlePaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(Offset(cx, note.currentY), radius, circlePaint);

    final arrowSize = radius * 0.55;
    final arrowPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    _drawArrow(canvas, cx, note.currentY, arrowSize, note.event.direction!, arrowPaint);
  }

  void _drawArrow(Canvas canvas, double cx, double cy, double size, SlideDirection dir, Paint paint) {
    final path = Path();
    switch (dir) {
      case SlideDirection.up:
        path.moveTo(cx, cy - size);
        path.lineTo(cx - size * 0.7, cy + size * 0.3);
        path.lineTo(cx + size * 0.7, cy + size * 0.3);
      case SlideDirection.down:
        path.moveTo(cx, cy + size);
        path.lineTo(cx - size * 0.7, cy - size * 0.3);
        path.lineTo(cx + size * 0.7, cy - size * 0.3);
      case SlideDirection.left:
        path.moveTo(cx - size, cy);
        path.lineTo(cx + size * 0.3, cy - size * 0.7);
        path.lineTo(cx + size * 0.3, cy + size * 0.7);
      case SlideDirection.right:
        path.moveTo(cx + size, cy);
        path.lineTo(cx - size * 0.3, cy - size * 0.7);
        path.lineTo(cx - size * 0.3, cy + size * 0.7);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _paintExplode(Canvas canvas, ExplodeAnimation explode, double w) {
    final progress = explode.controller.value;
    final paint = Paint()..style = PaintingStyle.stroke;

    if (progress <= 0.08) {
      final t = progress / 0.08;
      final easedT = Curves.easeIn.transform(t);
      final currentRadius = explode.radius * (1.0 - easedT);

      if (currentRadius > 0.1) {
        paint.color = color.withValues(alpha: 0.3);
        paint.strokeWidth = 1.5;
        canvas.drawCircle(Offset(explode.x, explode.y), currentRadius, paint);
      }
    }

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
