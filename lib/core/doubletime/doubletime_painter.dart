import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'doubletime_models.dart';

/// 事件点击回调
typedef EventTapCallback = void Function(String eventId);

/// 跨小时连续色块模型
class _ContinuousBlock {
  final String eventId;
  final int colorArgb;
  final String title;
  final int startHour; // 起始小时
  final double startRatio; // 起始小时内的比例位置 (0..1)
  final int endHour; // 结束小时
  final double endRatio; // 结束小时内的比例位置 (0..1)

  _ContinuousBlock({
    required this.eventId,
    required this.colorArgb,
    required this.title,
    required this.startHour,
    required this.startRatio,
    required this.endHour,
    required this.endRatio,
  });
}

class DualTimelinePainter extends CustomPainter {
  final DateTime day;
  final Map<DoubleTimeLane, Map<DateTime, List<DoubleTimeHourAllocation>>>
      allocations;
  final double hourRowHeight;
  final double labelWidth;
  final double gutter;
  final double laneWidth;
  final bool hidePlanLane;
  final EventTapCallback? onEventTap;

  DualTimelinePainter({
    required this.day,
    required this.allocations,
    this.hourRowHeight = 56,
    this.labelWidth = 56,
    this.gutter = 12,
    this.laneWidth = 140,
    this.hidePlanLane = false,
    this.onEventTap,
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

    // 白色面板背景
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

    // 时间标签 + 网格线
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

    // 绘制通道标题
    if (!hidePlanLane) {
      _drawLaneTitle(canvas, 'Plan', planX, 4);
      _drawLanePassThrough(canvas, DoubleTimeLane.plan, planX, panelTop);
    }
    _drawLaneTitle(canvas, 'Actual', actualX, 4);
    _drawLanePassThrough(canvas, DoubleTimeLane.actual, actualX, panelTop);
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

  /// 将同一事件的多个小时格合并为连续色块，通行绘制
  List<_ContinuousBlock> _buildContinuousBlocks(DoubleTimeLane lane) {
    final laneMap =
        allocations[lane] ?? const <DateTime, List<DoubleTimeHourAllocation>>{};

    // 按 eventId 分组，保持插入顺序
    final eventAllocs = <String, List<DoubleTimeHourAllocation>>{};
    for (var hour = 0; hour < 24; hour++) {
      final cellStart = DateTime(day.year, day.month, day.day, hour);
      final items = laneMap[cellStart];
      if (items == null || items.isEmpty) continue;
      for (final alloc in items) {
        eventAllocs.putIfAbsent(alloc.eventId, () => []);
        eventAllocs[alloc.eventId]!.add(alloc);
      }
    }

    final blocks = <_ContinuousBlock>[];
    for (final entry in eventAllocs.entries) {
      final eventId = entry.key;
      final allocs = entry.value;
      if (allocs.isEmpty) continue;

      // 按 cellStart 排序
      allocs.sort((a, b) => a.cellStart.compareTo(b.cellStart));

      // 合并连续的小时段
      var startHour = allocs.first.cellStart.hour;
      var startRatio = 1.0 - allocs.first.ratio; // 占比转为起始偏移
      var endHour = allocs.last.cellStart.hour;
      var endRatio = allocs.last.ratio;

      // 如果有多个小时格且中间有间隔，拆分
      for (var i = 0; i < allocs.length; i++) {
        final alloc = allocs[i];
        if (i == 0) {
          startHour = alloc.cellStart.hour;
          startRatio = 1.0 - alloc.ratio;
          endHour = alloc.cellStart.hour;
          endRatio = alloc.ratio;
        } else {
          final prev = allocs[i - 1];
          final prevEnd = prev.cellStart.hour;
          final currentStart = alloc.cellStart.hour;
          if (currentStart == prevEnd + 1 ||
              currentStart == prevEnd) {
            // 连续
            endHour = alloc.cellStart.hour;
            endRatio = alloc.ratio;
          } else {
            // 不连续，保存当前块，开始新块
            blocks.add(_ContinuousBlock(
              eventId: eventId,
              colorArgb: allocs.first.colorArgb,
              title: allocs.first.title,
              startHour: startHour,
              startRatio: startRatio.clamp(0.0, 1.0),
              endHour: endHour,
              endRatio: endRatio.clamp(0.0, 1.0),
            ));
            startHour = alloc.cellStart.hour;
            startRatio = 1.0 - alloc.ratio;
            endHour = alloc.cellStart.hour;
            endRatio = alloc.ratio;
          }
        }
      }
      // 添加最后一个块
      blocks.add(_ContinuousBlock(
        eventId: eventId,
        colorArgb: allocs.first.colorArgb,
        title: allocs.first.title,
        startHour: startHour,
        startRatio: startRatio.clamp(0.0, 1.0),
        endHour: endHour,
        endRatio: endRatio.clamp(0.0, 1.0),
      ));
    }
    return blocks;
  }

  /// 通行绘制：连续色块跨小时不间断
  void _drawLanePassThrough(
    Canvas canvas,
    DoubleTimeLane lane,
    double x,
    double panelTop,
  ) {
    final blocks = _buildContinuousBlocks(lane);

    for (final block in blocks) {
      final blockTop = panelTop +
          (block.startHour + block.startRatio) * hourRowHeight +
          4;
      final blockBottom = panelTop +
          (block.endHour + block.endRatio) * hourRowHeight -
          4;

      final fillRect = Rect.fromLTRB(
        x + 8,
        blockTop + 2,
        x + laneWidth - 8,
        math.max(blockTop + 12, blockBottom - 2),
      );

      final paint = Paint()..color = Color(block.colorArgb);
      canvas.drawRRect(
        RRect.fromRectAndRadius(fillRect, const Radius.circular(10)),
        paint,
      );

      // 色块内标题文字
      if (fillRect.height > 20) {
        final titlePainter = TextPainter(
          text: TextSpan(
            text: block.title,
            style: TextStyle(
              color: _bestOnColor(Color(block.colorArgb)),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout(maxWidth: fillRect.width - 8);
        titlePainter.paint(
          canvas,
          Offset(fillRect.left + 6, fillRect.top + 4),
        );
      }
    }
  }

  /// 色块上的最佳文字颜色
  Color _bestOnColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? const Color(0xFF1A1A2E) : Colors.white;
  }

  @override
  bool shouldRepaint(covariant DualTimelinePainter oldDelegate) {
    return oldDelegate.day != day ||
        oldDelegate.allocations != allocations ||
        oldDelegate.hidePlanLane != hidePlanLane ||
        oldDelegate.onEventTap != onEventTap;
  }

  /// 检测色块点击
  String? hitTestEvent(Offset position, Size size) {
    final blocksPlan = _buildContinuousBlocks(DoubleTimeLane.plan);
    final blocksActual = _buildContinuousBlocks(DoubleTimeLane.actual);

    final actualX = hidePlanLane ? 56.0 : 56.0 + laneWidth + gutter;

    // 检测plan色块
    if (!hidePlanLane) {
      for (final block in blocksPlan) {
        final blockTop = 28.0 + (block.startHour + block.startRatio) * hourRowHeight + 4;
        final blockBottom = 28.0 + (block.endHour + block.endRatio) * hourRowHeight - 4;
        if (position.dx >= 56.0 + 8 &&
            position.dx <= 56.0 + laneWidth - 8 &&
            position.dy >= blockTop &&
            position.dy <= math.max(blockTop + 12, blockBottom - 2)) {
          return block.eventId;
        }
      }
    }

    // 检测actual色块
    for (final block in blocksActual) {
      final blockTop = 28.0 + (block.startHour + block.startRatio) * hourRowHeight + 4;
      final blockBottom = 28.0 + (block.endHour + block.endRatio) * hourRowHeight - 4;
      if (position.dx >= actualX + 8 &&
          position.dx <= actualX + laneWidth - 8 &&
          position.dy >= blockTop &&
          position.dy <= math.max(blockTop + 12, blockBottom - 2)) {
        return block.eventId;
      }
    }

    return null;
  }
}
