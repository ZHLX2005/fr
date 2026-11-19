import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import 'calendar_palette.dart';

const List<String> _kWeekdayNamesMondayFirst = [
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '日',
];
const List<String> _kWeekdayNamesSundayFirst = [
  '日',
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
];

List<String> calendarWeekdayLabels({required bool mondayFirst}) =>
    mondayFirst ? _kWeekdayNamesMondayFirst : _kWeekdayNamesSundayFirst;

/// 月视图：固定 6 行，月初/月末补邻月日期。
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.onSelected,
  });

  final DateTime month;
  final DateTime selectedDate;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final labels = calendarWeekdayLabels(mondayFirst: mondayFirst);
    final gridStart = calendarMonthGridStart(month, mondayFirst: mondayFirst);
    final today = calendarDateOnly(DateTime.now());

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WeekdayHeader(labels: labels, palette: palette),
        GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 42,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 46,
            crossAxisSpacing: 0,
            mainAxisSpacing: 0,
          ),
          itemBuilder: (context, index) {
            final date = gridStart.add(Duration(days: index));
            final inMonth = date.month == month.month;
            return _CalendarDayCell(
              date: date,
              selected: calendarDateKey(date) == calendarDateKey(selectedDate),
              today: calendarDateKey(date) == calendarDateKey(today),
              inMonth: inMonth,
              marked: markedDates.contains(calendarDateKey(date)),
              palette: palette,
              onTap: () => onSelected(date),
            );
          },
        ),
      ],
    );
  }
}

/// 收起态：只显示选中日期所在的一周。
class CalendarWeekStrip extends StatelessWidget {
  const CalendarWeekStrip({
    super.key,
    required this.selectedDate,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.onSelected,
  });

  final DateTime selectedDate;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final labels = calendarWeekdayLabels(mondayFirst: mondayFirst);
    final weekStart = calendarWeekStart(selectedDate, mondayFirst: mondayFirst);
    final today = calendarDateOnly(DateTime.now());

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WeekdayHeader(labels: labels, palette: palette),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _CalendarDayCell(
                  date: weekStart.add(Duration(days: i)),
                  selected:
                      calendarDateKey(weekStart.add(Duration(days: i))) ==
                      calendarDateKey(selectedDate),
                  today:
                      calendarDateKey(weekStart.add(Duration(days: i))) ==
                      calendarDateKey(today),
                  inMonth: true,
                  marked: markedDates.contains(
                    calendarDateKey(weekStart.add(Duration(days: i))),
                  ),
                  palette: palette,
                  onTap: () => onSelected(weekStart.add(Duration(days: i))),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.labels, required this.palette});

  final List<String> labels;
  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.selected,
    required this.today,
    required this.inMonth,
    required this.marked,
    required this.palette,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool inMonth;
  final bool marked;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    final textColor = selected
        ? Colors.white
        : !inMonth
        ? palette.textSecondary.withValues(alpha: 0.38)
        : weekend
        ? palette.textSecondary
        : palette.textPrimary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? palette.accent : Colors.transparent,
                shape: BoxShape.circle,
                border: today && !selected
                    ? Border.all(
                        color: palette.accent.withValues(alpha: 0.38),
                        width: 1.2,
                      )
                    : null,
              ),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 16,
                  height: 1,
                  color: textColor,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              height: 5,
              child: marked
                  ? Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.85)
                            : palette.accent.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
