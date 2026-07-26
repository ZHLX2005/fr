// 面板顶部弧形描边与高光。

import 'package:flutter/material.dart';

import 'lab_panel_colors.dart';

class PanelSurfacePainter extends CustomPainter {
  final double progress;
  final LabPanelColors colors;

  PanelSurfacePainter({required this.progress, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final waveDepth = (24.0 - progress * 12.0).clamp(10.0, 24.0);
    final path = Path()..moveTo(0, 0);
    path.quadraticBezierTo(
      size.width * 0.22,
      waveDepth,
      size.width * 0.5,
      waveDepth * 0.78,
    );
    path.quadraticBezierTo(size.width * 0.78, waveDepth * 0.52, size.width, 0);

    final edgePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: colors.isDark ? 0.18 : 0.95),
          colors.accentSoft.withValues(alpha: 0.38),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, waveDepth));
    canvas.drawPath(
      path,
      edgePaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final highlightPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: colors.isDark ? 0.10 : 0.42),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.08),
              radius: size.width * 0.48,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.08),
      size.width * 0.48,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant PanelSurfacePainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}
