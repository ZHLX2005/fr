import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calendar_grid.dart';
import 'calendar_palette.dart';

/// 跟手可折叠的月/周日历头。
///
/// 展开高度 = 6 行月历；收起高度 = 单周。拖动时直接改
/// [AnimationController.value]，松手再按速度/位置吸附到两端。
class CalendarCollapsibleMonth extends StatefulWidget {
  const CalendarCollapsibleMonth({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onSelected,
  });

  final DateTime month;
  final DateTime selectedDate;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<DateTime> onSelected;

  @override
  State<CalendarCollapsibleMonth> createState() =>
      _CalendarCollapsibleMonthState();
}

class _CalendarCollapsibleMonthState extends State<CalendarCollapsibleMonth>
    with SingleTickerProviderStateMixin {
  static const double _range =
      kCalendarMonthGridHeight - kCalendarWeekHeight;

  late final AnimationController _controller;
  double _dragStartValue = 1;
  double _dragStartY = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: widget.expanded ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant CalendarCollapsibleMonth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) {
      _animateTo(widget.expanded);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(bool expanded) {
    _controller.animateTo(
      expanded ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      curve: expanded ? Curves.easeOutCubic : Curves.easeInCubic,
    );
  }

  void _handleDragStart(DragStartDetails details) {
    _controller.stop();
    _dragStartValue = _controller.value;
    _dragStartY = details.globalPosition.dy;
    HapticFeedback.selectionClick();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.globalPosition.dy - _dragStartY;
    final next = (_dragStartValue + delta / _range).clamp(0.0, 1.0);
    _controller.value = next;
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final value = _controller.value;
    final target = velocity < -260
        ? false
        : velocity > 260
            ? true
            : value >= 0.5;
    _animateTo(target);
    if (widget.expanded != target) {
      widget.onExpandedChanged(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthContent = CalendarMonthGrid(
      month: widget.month,
      selectedDate: widget.selectedDate,
      markedDates: widget.markedDates,
      mondayFirst: widget.mondayFirst,
      palette: widget.palette,
      onSelected: widget.onSelected,
    );
    final weekContent = CalendarWeekStrip(
      selectedDate: widget.selectedDate,
      markedDates: widget.markedDates,
      mondayFirst: widget.mondayFirst,
      palette: widget.palette,
      onSelected: widget.onSelected,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: _handleDragStart,
      onVerticalDragUpdate: _handleDragUpdate,
      onVerticalDragEnd: _handleDragEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final value = _controller.value;
          final height =
              kCalendarWeekHeight + _range * value;
          final monthOpacity = value;
          final weekOpacity = 1 - value;

          return SizedBox(
            width: double.infinity,
            height: height,
            child: ClipRect(
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: kCalendarMonthGridHeight,
                    child: IgnorePointer(
                      ignoring: value < 0.5,
                      child: Opacity(
                        opacity: monthOpacity,
                        child: monthContent,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: kCalendarWeekHeight,
                    child: IgnorePointer(
                      ignoring: value >= 0.5,
                      child: Opacity(
                        opacity: weekOpacity,
                        child: weekContent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
