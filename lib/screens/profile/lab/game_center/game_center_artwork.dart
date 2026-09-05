// 游戏中心 — 程序化封面
//
// 封面三层优先级（2026-09-05 起接入皮肤管线）：
//   ① remoteCover（KV 远程封面，ve game-skin-admin 上传，见 game_center_skin_spec.dart）
//   ② backgroundPath（用户在 Lab 里给该 demo 设的自定义背景图）
//   ③ 程序化「专属渐变 + 装饰图案 + 主图标」兜底
// 有图时：BoxFit.cover 铺满；垫底用该游戏渐变（禁止纯黑）。
// 无图时：专属渐变兜底。压暗蒙版保证标题可读。
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
    this.remoteCover,
    this.iconSize = 44,
    this.showIcon = true,
  });

  final GameMeta meta;

  /// 用户自定义背景（本地绝对路径或 http URL），null 表示用程序化封面
  final String? backgroundPath;

  /// KV 远程封面（皮肤管线），优先级高于 [backgroundPath]。
  /// 由调用方从 gameCenterCoverOf(slug, small|large) 取得。
  final ImageProvider? remoteCover;

  final double iconSize;
  final bool showIcon;

  bool get _hasImage => backgroundPath != null && backgroundPath!.isNotEmpty;

  bool get _hasCover => remoteCover != null;

  bool get _usePhoto => _hasCover || _hasImage;

  Widget _gradientBase() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: meta.gradient,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      // 不在此裁切：让图片微外扩到卡片 Clip，吃掉圆角发丝缝
      clipBehavior: Clip.none,
      children: [
        // 垫底：永远是游戏渐变，禁止纯黑
        _gradientBase(),
        if (_hasCover)
          Positioned(
            left: -2,
            top: -2,
            right: -2,
            bottom: -2,
            child: Image(
              image: remoteCover!,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              // 失败：露出下层渐变，绝不回退成黑块
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          )
        else if (_hasImage)
          Positioned(
            left: -2,
            top: -2,
            right: -2,
            bottom: -2,
            child: DemoCoverImage(
              path: backgroundPath!,
              fit: BoxFit.cover,
              transparentFallback: true,
            ),
          )
        else
          Positioned.fill(
            child: CustomPaint(
              painter: _ArtPatternPainter(meta.pattern, scheme: scheme),
            ),
          ),
        // 压暗蒙版：保证标题/角标可读
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.onSurface.withValues(alpha: _usePhoto ? 0.22 : 0.06),
                  scheme.onSurface.withValues(alpha: _usePhoto ? 0.48 : 0.30),
                ],
              ),
            ),
          ),
        ),
        if (showIcon && !_usePhoto)
          Center(
            child: Icon(
              meta.icon,
              size: iconSize,
              color: scheme.surface.withValues(alpha: 0.92),
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
