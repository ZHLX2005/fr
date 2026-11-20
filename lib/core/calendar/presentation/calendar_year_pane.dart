import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import 'calendar_palette.dart';

/// 年视图：12 张迷你月卡（含今日环、任务标记、农历首日）。
///
/// 点卡片通过 [onMonthTap] 上报（携带卡片 RenderBox 全局矩形，供
/// 年→月容器变换转场取起点）；卡片外观组件 [CalendarMiniMonthCard]
/// 同时被 ghost 转场复用。
///
/// [gridTransform] / [staggerT] / [staggerTarget] 用于月→年容器变换：
/// 网格整体做 FLIP 汇聚（原型 .year-grid 的 transform 关键帧），其余
/// 卡片按与目标卡的距离错峰浮现（原型逐卡 opacity + delay）。
class CalendarYearPane extends StatelessWidget {
  const CalendarYearPane({
    super.key,
    required this.year,
    required this.today,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.onYearChanged,
    required this.onMonthTap,
    this.cardKeys,
    this.gridTransform,
    this.staggerT,
    this.staggerTarget = 0,
  });

  final int year;
  final DateTime today;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final ValueChanged<int> onYearChanged;
  final void Function(BuildContext cardContext, DateTime monthFirst) onMonthTap;

  /// 按月份序号（0-11）提供卡片 GlobalKey，供容器变换取终态矩形。
  final Map<int, GlobalKey>? cardKeys;

  /// 月→年汇聚：作用于卡片网格的变换矩阵（null = 恒等）。
  final Matrix4? gridTransform;

  /// 错峰浮现进度（0..1），null = 不启用（全部卡片完全可见）。
  final double? staggerT;

  /// 错峰基准卡片（目标月序 0-11）。
  final int staggerTarget;

  /// 原型：delay = 100+min(220, |i-target|*32) ms，时长 240ms，ease-out。
  double _cardOpacity(int i) {
    final t = staggerT;
    if (t == null) return 1;
    final elapsed = t.clamp(0.0, 1.0) * 520;
    final delay =
        100.0 + math.min(220.0, (i - staggerTarget).abs() * 32.0);
    final p = ((elapsed - delay) / 240).clamp(0.0, 1.0);
    return 1 - (1 - p) * (1 - p);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _YearArrow(
                icon: Icons.chevron_left,
                palette: palette,
                onTap: () => onYearChanged(year - 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  '$year',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              _YearArrow(
                icon: Icons.chevron_right,
                palette: palette,
                onTap: () => onYearChanged(year + 1),
              ),
            ],
          ),
        ),
        Expanded(
          child: Transform(
            alignment: Alignment.topLeft,
            transform: gridTransform ?? Matrix4.identity(),
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              padding: const EdgeInsets.fromLTRB(0, 2, 0, 116),
              childAspectRatio: 0.82,
              children: [
                for (var m = 1; m <= 12; m++)
                  Opacity(
                    opacity: _cardOpacity(m - 1),
                    child: CalendarMiniMonthCard(
                      key: cardKeys?[m - 1],
                      month: DateTime(year, m, 1),
                      today: today,
                      selectedDate: null,
                      markedDates: markedDates,
                      mondayFirst: mondayFirst,
                      palette: palette,
                      isCurrentMonth:
                          year == today.year && m == today.month,
                      onTap: () => onMonthTap(context, DateTime(year, m, 1)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _YearArrow extends StatelessWidget {
  const _YearArrow({
    required this.icon,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: palette.textSecondary),
      ),
    );
  }
}

/// 迷你月卡：label + 迷你日历（固定 6 行布局保证卡片等高）。
class CalendarMiniMonthCard extends StatelessWidget {
  const CalendarMiniMonthCard({
    super.key,
    required this.month,
    required this.today,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    this.selectedDate,
    this.isCurrentMonth = false,
    this.onTap,
  });

  final DateTime month;
  final DateTime today;
  final DateTime? selectedDate;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final bool isCurrentMonth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              '${month.month}月',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isCurrentMonth ? FontWeight.w700 : FontWeight.w500,
                color: isCurrentMonth
                    ? palette.accent
                    : palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Column(
                children: [
                  for (var row = 0; row < 6; row++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var col = 0; col < 7; col++)
                            Expanded(
                              child: Center(
                                child: _MiniCell(
                                  date: _cellDate(month, row, col),
                                  month: month,
                                  today: today,
                                  selectedDate: selectedDate,
                                  markedDates: markedDates,
                                  palette: palette,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _cellDate(DateTime month, int row, int col) {
    final start = calendarMonthGridStart(month, mondayFirst: mondayFirst);
    return start.add(Duration(days: row * 7 + col));
  }
}

class _MiniCell extends StatelessWidget {
  const _MiniCell({
    required this.date,
    required this.month,
    required this.today,
    required this.selectedDate,
    required this.markedDates,
    required this.palette,
  });

  final DateTime date;
  final DateTime month;
  final DateTime today;
  final DateTime? selectedDate;
  final Set<String> markedDates;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    if (date.month != month.month) {
      return const SizedBox.shrink();
    }
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final isSelected = selectedDate != null &&
        date.year == selectedDate!.year &&
        date.month == selectedDate!.month &&
        date.day == selectedDate!.day;
    final hasTask = markedDates.contains(calendarDateKey(date));

    final color = isToday
        ? palette.danger
        : (isSelected ? palette.accent : (hasTask ? palette.accent : null));
    return Container(
      width: 17,
      height: 17,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected && !isToday
            ? palette.accentSoft.withValues(alpha: 0.5)
            : null,
        border: isToday
            ? Border.all(color: palette.danger, width: 1)
            : null,
      ),
      child: Text(
        '${date.day}',
        style: TextStyle(
          fontSize: 8.5,
          height: 1,
          fontFeatures: const [],
          color: color ?? palette.textSecondary,
          fontWeight: isToday || hasTask ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
