// 游戏中心 — 程序化封面
//
// 项目没有美术资源，但"每张卡长一样"正是 demo 感的来源。这里用
// 「专属渐变 + 装饰图案 + 主图标」给每款游戏生成可辨识的封面；
// 用户若在 Lab 里给该 demo 设过自定义背景图（LabCardProvider），
// 则优先用图片 + 压暗蒙版，保证标题文字始终可读。
//
// 配色 / 图标 / 图案的登记表在 const_game_center.dart。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../demo_cover_image.dart';
import 'const_game_center.dart';

class GameArtwork extends StatelessWidget {
  const GameArtwork({
    super.key,
    required this.meta,
    this.backgroundPath,
    this.iconSize = 44,
    this.showIcon = true,
  });

  final GameMeta meta;

  /// 用户自定义背景（本地绝对路径或 http URL），null 表示用程序化封面
  final String? backgroundPath;

  final double iconSize;
  final bool showIcon;

  bool get _hasImage => backgroundPath != null && backgroundPath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 底：渐变（自定义图加载失败时也不会露白）
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: meta.gradient,
            ),
          ),
        ),
        if (_hasImage)
          // 透明兜底：加载中/失败时露出下层专属渐变，不需要占位底色
          Positioned.fill(
            child: DemoCoverImage(
              path: backgroundPath!,
              transparentFallback: true,
            ),
          )
        else
          Positioned.fill(
            child: CustomPaint(painter: _ArtPatternPainter(meta.pattern, scheme: Theme.of(context).colorScheme)),
          ),
        // 压暗蒙版：让上层白色文字/角标在任何底色上都可读
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: _hasImage ? 0.28 : 0.06),
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: _hasImage ? 0.55 : 0.30),
                ],
              ),
            ),
          ),
        ),
        if (showIcon && !_hasImage)
          Center(
            child: Icon(
              meta.icon,
              size: iconSize,
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
            ),
          ),
      ],
    );
  }
}

/// 装饰图案画笔。全部用白色低透明度绘制，叠在渐变之上。
class _ArtPatternPainter extends CustomPainter {
  _ArtPatternPainter(this.pattern, {required this.scheme});

  /// 主题色板（CustomPainter 无 BuildContext，由 build() 注入）
  final ColorScheme scheme;

  final GameArtPattern pattern;

  @override
  void paint(Canvas canvas, Size size) {
    switch (pattern) {
      case GameArtPattern.blob:
        _paintBlob(canvas, size);
      case GameArtPattern.stripes:
        _paintStripes(canvas, size);
      case GameArtPattern.grid:
        _paintGrid(canvas, size);
      case GameArtPattern.dots:
        _paintDots(canvas, size);
      case GameArtPattern.wave:
        _paintWave(canvas, size);
    }
  }

  void _paintBlob(Canvas canvas, Size size) {
    final paint = Paint()..color = scheme.surface.withValues(alpha: 0.10);
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.22),
      size.shortestSide * 0.34,
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.74),
      size.shortestSide * 0.44,
      paint..color = scheme.surface.withValues(alpha: 0.07),
    );
    canvas.drawCircle(
      Offset(size.width * 0.72, size.height * 0.14),
      size.shortestSide * 0.16,
      paint..color = scheme.surface.withValues(alpha: 0.12),
    );
  }

  void _paintStripes(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = scheme.surface.withValues(alpha: 0.09)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke;
    const step = 26.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = scheme.surface.withValues(alpha: 0.14)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const divisions = 6;
    for (int i = 1; i < divisions; i++) {
      final dx = size.width * i / divisions;
      final dy = size.height * i / divisions;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  void _paintDots(Canvas canvas, Size size) {
    final paint = Paint()..color = scheme.surface.withValues(alpha: 0.16);
    const cols = 7;
    final rows = math.max(3, (cols * size.height / size.width).round());
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        canvas.drawCircle(
          Offset(size.width * (c + 0.5) / cols, size.height * (r + 0.5) / rows),
          2.2,
          paint,
        );
      }
    }
  }

  void _paintWave(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = scheme.surface.withValues(alpha: 0.16)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (int line = 0; line < 3; line++) {
      final path = Path();
      final baseY = size.height * (0.35 + line * 0.18);
      final amp = size.height * (0.10 - line * 0.02);
      path.moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += 6) {
        final y = baseY + math.sin((x / size.width) * math.pi * 3) * amp;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ArtPatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern;
}
