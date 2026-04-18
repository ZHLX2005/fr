import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'doubletime_mapper.dart';
import 'doubletime_models.dart';

class DualTimelinePainter extends CustomPainter {
  final DateTime day;
  final Map<DoubleTimeLane, Map<DateTime, List<DoubleTimeHourAllocation>>>
  allocations;
  final double hourRowHeight;
  final double labelWidth;
  final double gutter;
  final double laneWidth;
  final bool hidePlanLane;

  DualTimelinePainter({
    required this.day,
    required this.allocations,
    this.hourRowHeight = 56,
    this.labelWidth = 56,
    this.gutter = 12,
    this.laneWidth = 140,
    this.hidePlanLane = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF4F7FB);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final gridPaint = Paint()
      ..color = const Color(0xFFDBE4F0)
      ..strokeWidth = 1;

    final panelPaint = Paint()..color = Colors.white;
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);

    final timeLabelX = 0.0;
    final planX = timeLabelX + labelWidth;
    final actualX = hidePlanLane ? planX : planX + laneWidth + gutter;
    final panelTop = 28.0;
    final panelHeight = 24 * hourRowHeight;

    if (!hidePlanLane) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(planX, panelTop, laneWidth, panelHeight),
          const Radius.circular(18),
        ),
        panelPaint,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(actualX, panelTop, laneWidth, panelHeight),
        const Radius.circular(18),
      ),
      panelPaint,
    );

    for (var hour = 0; hour <= 24; hour++) {
      final y = panelTop + hour * hourRowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);

      if (hour < 24) {
        labelPainter.text = TextSpan(
          text: '${hour.toString().padLeft(2, '0')}:00',
          style: const TextStyle(
            color: Color(0xFF66758A),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        );
        labelPainter.layout(maxWidth: labelWidth - 8);
        labelPainter.paint(canvas, Offset(6, y + hourRowHeight / 2 - 8));
      }
    }

    if (!hidePlanLane) {
      _drawLaneTitle(canvas, 'Plan', planX, 4);
      _drawLane(canvas, DoubleTimeLane.plan, planX, panelTop);
    }
    _drawLaneTitle(canvas, 'Actual', actualX, 4);
    _drawLane(canvas, DoubleTimeLane.actual, actualX, panelTop);
  }

  void _drawLaneTitle(Canvas canvas, String title, double x, double y) {
    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: laneWidth);
    painter.paint(canvas, Offset(x + 8, y));
  }

  void _drawLane(
    Canvas canvas,
    DoubleTimeLane lane,
    double x,
    double panelTop,
  ) {
    final laneMap =
        allocations[lane] ?? const <DateTime, List<DoubleTimeHourAllocation>>{};

    for (var hour = 0; hour < 24; hour++) {
      final cellStart = DateTime(day.year, day.month, day.day, hour);
      final cellTop = panelTop + hour * hourRowHeight;
      final cellRect = Rect.fromLTWH(
        x + 8,
        cellTop + 4,
        laneWidth - 16,
        hourRowHeight - 8,
      );
      final items = laneMap[cellStart];
      if (items == null || items.isEmpty) {
        continue;
      }

      final slices = stackCell(items);
      for (final slice in slices) {
        final fillTop = cellRect.top + slice.start * cellRect.height;
        final fillBottom = cellRect.top + slice.end * cellRect.height;
        final fillRect = Rect.fromLTRB(
          cellRect.left,
          fillTop + 2,
          cellRect.right,
          math.max(fillTop + 8, fillBottom - 2),
        );
        final paint = Paint()..color = Color(slice.colorArgb);
        canvas.drawRRect(
          RRect.fromRectAndRadius(fillRect, const Radius.circular(10)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant DualTimelinePainter oldDelegate) {
    return oldDelegate.day != day ||
        oldDelegate.allocations != allocations ||
        oldDelegate.hidePlanLane != hidePlanLane;
  }
}
