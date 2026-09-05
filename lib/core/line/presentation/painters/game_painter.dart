import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../domain/constants.dart';
import '../../domain/note_event.dart';
import '../falling_note.dart';

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
  final int gameElapsed; // 用于脉冲动画 / 音符位置（权威时钟）
  final double judgeLineFlash; // 0~1 命中闪白
  final int currentCombo;

  /// 主题色板（CustomPainter 无 BuildContext，由 build() 注入）
  final ColorScheme scheme;

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
    required this.scheme,
    this.judgeLineFlash = 0.0,
    this.currentCombo = 0,
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
    final flash = judgeLineFlash.clamp(0.0, 1.0);
    final judgePaint = Paint()
      ..color = Color.lerp(
        color.withValues(alpha: 0.25),
        scheme.onSurface.withValues(alpha: 0.9),
        flash,
      )!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 + flash * 2.5;
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

    // 6. 判定文字反馈（固定位置 + 上浮渐隐）
    for (final fb in judgeFeedbacks) {
      final progress = fb.controller.value;
      final alpha = fb.baseAlpha * (1.0 - progress);
      if (alpha <= 0.01) continue;

      final floatOffset = progress * 36.0 * screenWidth / 750;
      final pop = 1.0 + (1.0 - progress) * 0.18 * fb.fontScale;

      final textSpan = TextSpan(
        text: fb.text,
        style: TextStyle(
          fontSize: (14 + 4 * fb.fontScale) * pop * screenWidth / 750,
          fontWeight: FontWeight.w600,
          color: fb.color.withValues(alpha: alpha),
          letterSpacing: 1.5,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(fb.x - tp.width / 2, fb.y - floatOffset - tp.height / 2),
      );
      tp.dispose();

      if (fb.hintText != null && fb.hintText!.isNotEmpty) {
        final hint = TextPainter(
          text: TextSpan(
            text: fb.hintText,
            style: TextStyle(
              fontSize: 9 * screenWidth / 750,
              fontWeight: FontWeight.w400,
              color: fb.color.withValues(alpha: alpha * 0.7),
              letterSpacing: 1.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        hint.paint(
          canvas,
          Offset(
            fb.x - hint.width / 2,
            fb.y - floatOffset - tp.height / 2 - hint.height - 2,
          ),
        );
        hint.dispose();
      }
    }

    // 7. 连击数（中央偏上）
    if (currentCombo >= 2) {
      final comboTp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$currentCombo',
              style: TextStyle(
                fontSize: 22 * screenWidth / 750,
                fontWeight: FontWeight.w300,
                color: color.withValues(alpha: 0.55),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            TextSpan(
              text: ' COMBO',
              style: TextStyle(
                fontSize: 10 * screenWidth / 750,
                fontWeight: FontWeight.w200,
                color: color.withValues(alpha: 0.35),
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      comboTp.paint(
        canvas,
        Offset(w / 2 - comboTp.width / 2, judgeY * 0.42),
      );
      comboTp.dispose();
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
    canvas.drawLine(
      Offset(barX, dotTop + 4),
      Offset(barX, dotTop + 4 + barHeight),
      lineBgPaint,
    );

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

  /// 权威时钟下落位置（与判定同源）
  double _noteTravelY(FallingNote note) {
    final noteElapsed = gameElapsed - note.spawnElapsed;
    final actualDropMs = dropDuration / scrollSpeed;
    final travelPerMs = (screenHeight + 2 * radius) / actualDropMs;
    return -radius + travelPerMs * noteElapsed;
  }

  double _travelPerMs() {
    final actualDropMs = dropDuration / scrollSpeed;
    return (screenHeight + 2 * radius) / actualDropMs;
  }

  /// 越过判定线后的淡出系数（1→0）
  double _pastJudgeFade(double y, {double base = 1.0}) {
    if (y <= judgeY) return base;
    final fadeRange = screenHeight * 0.25;
    return base * (1.0 - ((y - judgeY) / fadeRange).clamp(0.0, 1.0));
  }

  /// Tap：双环 + 芯点，接近判定线时轻微呼吸，语义=「点按」
  void _paintTapNote(Canvas canvas, double cx, FallingNote note) {
    if (note.judged || note.removeMe) return;
    final y = _noteTravelY(note);
    if (y < -radius || y > screenHeight + radius) return;

    final alpha = _pastJudgeFade(y, base: 0.42);
    if (alpha <= 0.01) return;

    final approach = (1.0 - ((judgeY - y).abs() / (screenHeight * 0.35)))
        .clamp(0.0, 1.0);
    final pulse =
        1.0 + 0.04 * approach * math.sin(gameElapsed / 90.0 * math.pi);
    final r = radius * pulse;
    final center = Offset(cx, y);

    // 外环
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    // 内环（更细、更淡）
    canvas.drawCircle(
      center,
      r * 0.62,
      Paint()
        ..color = color.withValues(alpha: alpha * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // 中心实心点
    canvas.drawCircle(
      center,
      r * 0.12,
      Paint()
        ..color = color.withValues(alpha: alpha * 0.85)
        ..style = PaintingStyle.fill,
    );
    // 接近判定线时极淡填充
    if (approach > 0.35) {
      canvas.drawCircle(
        center,
        r * 0.92,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.06 * approach)
          ..style = PaintingStyle.fill,
      );
    }
  }

  /// Hold：更宽轨道 + 实心头尾，语义=「按住」
  void _paintHoldNote(Canvas canvas, double cx, FallingNote note) {
    final travelPerMs = _travelPerMs();
    final headY = _noteTravelY(note);
    final duration = note.event.holdDuration ?? 0;
    if (duration <= 0) return;

    final tailOffset = travelPerMs * duration;
    var tailY = headY - tailOffset;
    if (tailY > screenHeight + radius && headY > screenHeight + radius) return;
    if (headY < -radius * 2) return;

    final minVisibleY = -radius * 2;
    if (tailY < minVisibleY) tailY = minVisibleY;

    // 轨道接近列宽，头圆略大于 tap，更「大气」
    final bodyHalf = radius * 0.92;
    final headR = radius * 1.12;

    double progress = 0.0;
    if (note.holdFadeOut > 0) {
      progress = note.holdProgress.clamp(0.0, 1.0);
    } else if (note.holdPressTime > 0) {
      final held = (gameElapsed - note.holdPressTime).clamp(0, duration);
      progress = (held / duration).clamp(0.0, 1.0);
    }

    double alpha;
    if (note.holdFadeOut > 0) {
      alpha = 0.62 * (1.0 - note.holdFadeOut * 0.35);
    } else if (note.holding) {
      alpha = 0.78 * (1.0 - progress * 0.28).clamp(0.35, 1.0);
    } else {
      alpha = 0.62;
    }
    if (alpha < 0.01) return;

    final bodyTop = tailY;
    final bodyBottom = headY - headR * 0.28;
    final bodyH = (bodyBottom - bodyTop).clamp(0.0, double.infinity);

    // ── 轨道外轮廓 ──
    if (bodyH > 2) {
      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - bodyHalf, bodyTop, bodyHalf * 2, bodyH),
        Radius.circular(bodyHalf),
      );
      canvas.drawRRect(
        track,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.22)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        track,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6,
      );

      // 侧刻度
      final tickPaint = Paint()
        ..color = color.withValues(alpha: alpha * 0.35)
        ..strokeWidth = 1.4;
      final tickStep = math.max(16.0, radius * 0.75);
      for (double ty = bodyBottom - tickStep; ty > bodyTop + 4; ty -= tickStep) {
        canvas.drawLine(
          Offset(cx - bodyHalf * 0.62, ty),
          Offset(cx + bodyHalf * 0.62, ty),
          tickPaint,
        );
      }
    }

    // ── 进度填充（从头向上）──
    if (note.holdPressTime > 0 && progress > 0 && bodyH > 2) {
      final fillH = bodyH * progress;
      final fillTop = bodyBottom - fillH;
      final fillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - bodyHalf, fillTop, bodyHalf * 2, fillH),
        Radius.circular(bodyHalf),
      );

      canvas.drawRRect(
        fillRect,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.45)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            8.0 + 14.0 * progress,
          ),
      );
      canvas.drawRRect(
        fillRect,
        Paint()
          ..color = color.withValues(alpha: alpha * (0.45 + 0.3 * progress))
          ..style = PaintingStyle.fill,
      );

      if (progress < 1.0) {
        canvas.drawLine(
          Offset(cx - bodyHalf * 0.9, fillTop),
          Offset(cx + bodyHalf * 0.9, fillTop),
          Paint()
            ..color = scheme.surface.withValues(alpha: alpha * 0.85)
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // 无尾盘：轨道顶端圆角即结束，不画释放点圆盘

    // ── 头圆（按下点）──
    final headPulse = note.holding
        ? 1.0 + 0.06 * math.sin(gameElapsed / 70.0 * math.pi)
        : 1.0;
    final headCenter = Offset(cx, headY);
    final hr = headR * headPulse;

    canvas.drawCircle(
      headCenter,
      hr,
      Paint()
        ..color = color.withValues(alpha: alpha * (note.holding ? 0.28 : 0.16))
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      headCenter,
      hr,
      Paint()
        ..color = color.withValues(alpha: alpha * (note.holding ? 1.0 : 0.88))
        ..style = PaintingStyle.stroke
        ..strokeWidth = note.holding ? 3.4 : 2.8,
    );
    canvas.drawCircle(
      headCenter,
      hr * 0.48,
      Paint()
        ..color = color.withValues(alpha: alpha * (note.holding ? 0.35 : 0.18))
        ..style = PaintingStyle.fill,
    );
    // 头内十字微标（与 tap 双环区分）
    final cross = Paint()
      ..color = color.withValues(alpha: alpha * 0.65)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final c = hr * 0.28;
    canvas.drawLine(Offset(cx - c, headY), Offset(cx + c, headY), cross);
    canvas.drawLine(Offset(cx, headY - c), Offset(cx, headY + c), cross);

    if (note.holdFadeOut > 0) {
      _paintHoldNoteParticles(canvas, cx, headY, alpha, note.holdFadeOut);
    }
  }

  void _paintHoldNoteParticles(
    Canvas canvas,
    double cx,
    double headY,
    double alpha,
    double fadeOut,
  ) {
    if (fadeOut <= 0) return;

    final flicker = 0.8 + 0.2 * math.sin(fadeOut * math.pi * 30);
    final flickerAlpha = alpha * flicker * (1.0 - fadeOut);
    if (flickerAlpha < 0.01) return;

    const particleCount = 10;
    for (int i = 0; i < particleCount; i++) {
      final baseAngle = (2 * math.pi * i / particleCount);
      final speed = 42.0 + (i % 3) * 12.0;
      final vx = math.cos(baseAngle) * speed * (1 - fadeOut * 0.5);
      final vy =
          math.sin(baseAngle) * speed * (1 - fadeOut * 0.5) - 22 * fadeOut;
      final px = cx + vx * fadeOut * 0.32;
      final py = headY + vy * fadeOut * 0.32;
      final particleAlpha = (1 - fadeOut) * 0.85;
      final particleSize = 2.0 + (i % 2) * 1.4;

      if (particleAlpha > 0.01) {
        canvas.drawCircle(
          Offset(px, py),
          particleSize * (1 - fadeOut * 0.3),
          Paint()
            ..color = Color.lerp(
              color,
              scheme.surface,
              0.25,
            )!.withValues(alpha: particleAlpha)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  /// Slide：放大菱形 + 粗箭头，语义=「滑动」
  void _paintSlideNote(Canvas canvas, double cx, FallingNote note) {
    if (note.judged || note.removeMe) return;
    final y = _noteTravelY(note);
    if (y < -radius || y > screenHeight + radius) return;

    final alpha = _pastJudgeFade(y, base: 0.72);
    if (alpha <= 0.01) return;

    final dir = note.event.direction ?? SlideDirection.up;
    final center = Offset(cx, y);
    // 明显大于 tap，避免「看不见」
    final r = radius * 1.38;

    // 菱形外框
    final diamond = Path()
      ..moveTo(cx, y - r)
      ..lineTo(cx + r * 0.82, y)
      ..lineTo(cx, y + r)
      ..lineTo(cx - r * 0.82, y)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()
        ..color = color.withValues(alpha: alpha * 0.22)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      diamond,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeJoin = StrokeJoin.round,
    );

    // 内虚线圆
    _drawDashedCircle(
      canvas,
      center,
      r * 0.55,
      Paint()
        ..color = color.withValues(alpha: alpha * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
      dashCount: 10,
      dashRatio: 0.5,
    );

    // 方向箭头（更大）
    _drawArrow(
      canvas,
      cx,
      y,
      r * 0.58,
      dir,
      Paint()..color = color.withValues(alpha: alpha * 0.98),
    );
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double r,
    Paint paint, {
    int dashCount = 12,
    double dashRatio = 0.5,
  }) {
    final path = Path();
    final step = (2 * math.pi) / dashCount;
    final dashLen = step * dashRatio;
    for (int i = 0; i < dashCount; i++) {
      final a0 = -math.pi / 2 + i * step;
      final a1 = a0 + dashLen;
      path.moveTo(
        center.dx + r * math.cos(a0),
        center.dy + r * math.sin(a0),
      );
      path.arcTo(
        Rect.fromCircle(center: center, radius: r),
        a0,
        a1 - a0,
        false,
      );
    }
    canvas.drawPath(path, paint);
  }

  void _drawArrow(
    Canvas canvas,
    double cx,
    double cy,
    double size,
    SlideDirection dir,
    Paint paint,
  ) {
    final shaft = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.32
      ..strokeCap = StrokeCap.round;
    final head = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    late Offset tip;
    late Offset base;
    late Offset left;
    late Offset right;

    switch (dir) {
      case SlideDirection.up:
        tip = Offset(cx, cy - size);
        base = Offset(cx, cy + size * 0.55);
        left = Offset(cx - size * 0.48, cy - size * 0.15);
        right = Offset(cx + size * 0.48, cy - size * 0.15);
      case SlideDirection.down:
        tip = Offset(cx, cy + size);
        base = Offset(cx, cy - size * 0.55);
        left = Offset(cx - size * 0.48, cy + size * 0.15);
        right = Offset(cx + size * 0.48, cy + size * 0.15);
      case SlideDirection.left:
        tip = Offset(cx - size, cy);
        base = Offset(cx + size * 0.55, cy);
        left = Offset(cx - size * 0.15, cy - size * 0.48);
        right = Offset(cx - size * 0.15, cy + size * 0.48);
      case SlideDirection.right:
        tip = Offset(cx + size, cy);
        base = Offset(cx - size * 0.55, cy);
        left = Offset(cx + size * 0.15, cy - size * 0.48);
        right = Offset(cx + size * 0.15, cy + size * 0.48);
    }

    canvas.drawLine(base, Offset.lerp(base, tip, 0.72)!, shaft);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, head);
  }

  void _paintExplode(Canvas canvas, ExplodeAnimation explode, double w) {
    final progress = explode.controller.value;
    final paint = Paint()..style = PaintingStyle.stroke;
    final baseAlpha = explode.weak ? 0.18 : 0.3;

    if (progress <= 0.08) {
      final t = progress / 0.08;
      final easedT = Curves.easeIn.transform(t);
      final currentRadius = explode.radius * (1.0 - easedT);

      if (currentRadius > 0.1) {
        paint.color = color.withValues(alpha: baseAlpha);
        paint.strokeWidth = explode.weak ? 1.2 : 1.65;
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
