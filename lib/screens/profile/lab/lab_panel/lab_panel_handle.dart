// 面板把手：胶囊 + 状态圈。形态按帧跟 progress 变，自订阅不牵动面板重建。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'const_lab_panel.dart';
import 'lab_panel_colors.dart';
import 'lab_panel_state_machine.dart';

/// progress 的纯函数：与 LabPullPanelStateMachine.closeProgress 同一公式。
/// 把手要按帧变形，走 notifier 自己算，避免为此逐帧 setState 整个面板。
double panelCloseProgress(double progress) {
  if (progress >= 1.0) return 0.0;
  return ((1.0 - progress) / LabPullPanelMetrics.openThreshold).clamp(0.0, 1.0);
}

class PanelHandle extends StatelessWidget {
  final LabPanelColors panelColors;
  final ValueListenable<double> progress;
  final bool showCloseCue;

  const PanelHandle({
    super.key,
    required this.panelColors,
    required this.progress,
    required this.showCloseCue,
  });

  @override
  Widget build(BuildContext context) {
    final pc = panelColors;
    final strokeColor = pc.accentDeep;
    final bgColor = pc.accent.withValues(alpha: 0.12);

    return ValueListenableBuilder<double>(
      valueListenable: progress,
      builder: (context, value, _) {
        final closeProgress = panelCloseProgress(value);
        final readyToOpen = value >= LabPullPanelMetrics.openThreshold;
        final handleWidth =
            kLabHandleWidthBase +
            value * kLabHandleWidthGain -
            closeProgress * kLabHandleWidthShrink;
        final handleHeight =
            kLabHandleHeightBase + value * kLabHandleHeightGain;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: kLabHandleAnimDuration,
              curve: Curves.easeOut,
              width: handleWidth.clamp(kLabHandleWidthMin, kLabHandleWidthMax),
              height: handleHeight.clamp(
                kLabHandleHeightBase,
                kLabHandleHeightMax,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.88),
                    pc.accentSoft.withValues(alpha: 0.68),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: pc.accentDeep.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: kLabHandleRingSize,
              height: kLabHandleRingSize,
              child: CustomPaint(
                painter: _HandleStatePainter(
                  progress: readyToOpen ? 1.0 : value.clamp(0.0, 1.0),
                  closeProgress: closeProgress,
                  strokeColor: strokeColor,
                  bgColor: bgColor,
                  readyToOpen: readyToOpen,
                  showCloseCue: showCloseCue,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HandleStatePainter extends CustomPainter {
  final double progress;
  final double closeProgress;
  final Color strokeColor;
  final Color bgColor;
  final bool readyToOpen;
  final bool showCloseCue;

  _HandleStatePainter({
    required this.progress,
    required this.closeProgress,
    required this.strokeColor,
    required this.bgColor,
    required this.readyToOpen,
    required this.showCloseCue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;

    final basePaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, basePaint);

    final activePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = readyToOpen ? 4 : 3;

    final sweep = readyToOpen ? 2 * math.pi : math.pi * 2 * progress;
    if (sweep > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        activePaint,
      );
    }

    if (readyToOpen) {
      final dotPaint = Paint()..color = strokeColor;
      canvas.drawCircle(center, 4.5, dotPaint);
      return;
    }

    final cuePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.8;

    final direction = showCloseCue ? -1.0 : 1.0;
    final spread = 7 + closeProgress * 4;
    final path = Path()
      ..moveTo(center.dx - 7, center.dy - spread * direction * 0.2)
      ..lineTo(center.dx, center.dy + spread * direction * 0.45)
      ..lineTo(center.dx + 7, center.dy - spread * direction * 0.2);
    canvas.drawPath(path, cuePaint);
  }

  @override
  bool shouldRepaint(covariant _HandleStatePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        closeProgress != oldDelegate.closeProgress ||
        strokeColor != oldDelegate.strokeColor ||
        bgColor != oldDelegate.bgColor ||
        readyToOpen != oldDelegate.readyToOpen ||
        showCloseCue != oldDelegate.showCloseCue;
  }
}
