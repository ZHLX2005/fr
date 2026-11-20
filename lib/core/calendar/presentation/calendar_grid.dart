import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import 'calendar_palette.dart';

const List<String> _kWeekdayNamesMondayFirst = ['一', '二', '三', '四', '五', '六', '日'];
const List<String> _kWeekdayNamesSundayFirst = ['日', '一', '二', '三', '四', '五', '六'];

const double kCalendarWeekdayHeaderHeight = 28;
const double kCalendarDayCellHeight = 58;
const double kCalendarWeekCellHeight = 72;
const double kCalendarMonthGridHeight =
    kCalendarWeekdayHeaderHeight + kCalendarDayCellHeight * 6;
const double kCalendarWeekHeight =
    kCalendarWeekdayHeaderHeight + kCalendarWeekCellHeight;

List<String> calendarWeekdayLabels({required bool mondayFirst}) =>
    mondayFirst ? _kWeekdayNamesMondayFirst : _kWeekdayNamesSundayFirst;

/// 只有少量固定公历节日，用于还原参考图里的日期下方小字。
String? calendarHolidayLabel(DateTime date) {
  final key = '${date.month}-${date.day}';
  const fixed = {
    '1-1': '元旦',
    '2-14': '情人节',
    '3-8': '妇女节',
    '4-1': '愚人节',
    '5-1': '劳动节',
    '6-1': '儿童节',
    '10-1': '国庆节',
    '10-31': '万圣节',
    '11-26': '感恩节',
    '12-25': '圣诞节',
  };
  if (fixed.containsKey(key)) return fixed[key];
  if (date.year == 2026 && date.month == 10 && date.day == 18) {
    return '重阳节';
  }
  return null;
}

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
    this.showHolidays = true,
  });

  final DateTime month;
  final DateTime selectedDate;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final ValueChanged<DateTime> onSelected;
  final bool showHolidays;

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
            mainAxisExtent: kCalendarDayCellHeight,
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
              holiday: showHolidays && inMonth ? calendarHolidayLabel(date) : null,
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
                child: _WeekDayCell(
                  date: weekStart.add(Duration(days: i)),
                  selected: calendarDateKey(weekStart.add(Duration(days: i))) ==
                      calendarDateKey(selectedDate),
                  today: calendarDateKey(weekStart.add(Duration(days: i))) ==
                      calendarDateKey(today),
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

/// 3 日视图：以选中日期为中心，左右各一天。
class CalendarThreeDayStrip extends StatelessWidget {
  const CalendarThreeDayStrip({
    super.key,
    required this.selectedDate,
    required this.markedDates,
    required this.palette,
    required this.onSelected,
  });

  final DateTime selectedDate;
  final Set<String> markedDates;
  final CalendarPalette palette;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final start = selectedDate.subtract(const Duration(days: 1));
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: _ThreeDayCell(
                date: start.add(Duration(days: i)),
                selected: i == 1,
                marked: markedDates.contains(
                  calendarDateKey(start.add(Duration(days: i))),
                ),
                weekday: weekdays[start.add(Duration(days: i)).weekday - 1],
                palette: palette,
                onTap: () => onSelected(start.add(Duration(days: i))),
              ),
            ),
        ],
      ),
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
      height: kCalendarWeekdayHeaderHeight,
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1,
                    color: palette.textSecondary.withValues(alpha: 0.72),
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
    required this.holiday,
    required this.palette,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool inMonth;
  final bool marked;
  final String? holiday;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final weekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
    final textColor = selected
        ? Colors.white
        : !inMonth
            ? palette.textSecondary.withValues(alpha: 0.35)
            : today
                ? palette.accent
                : weekend
                    ? palette.textSecondary
                    : palette.textPrimary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: kCalendarDayCellHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? palette.accent : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 18,
                  height: 1,
                  color: textColor,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 11,
              child: holiday != null
                  ? Text(
                      holiday!,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1,
                        color: selected
                            ? Colors.white.withValues(alpha: 0.9)
                            : palette.accent,
                      ),
                    )
                  : marked
                      ? Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white.withValues(alpha: 0.85)
                                : palette.accent.withValues(alpha: 0.7),
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

class _WeekDayCell extends StatelessWidget {
  const _WeekDayCell({
    required this.date,
    required this.selected,
    required this.today,
    required this.marked,
    required this.palette,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool today;
  final bool marked;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: kCalendarWeekCellHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? palette.accent : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${date.day}',
                style: TextStyle(
                  fontSize: 19,
                  height: 1,
                  color: selected
                      ? Colors.white
                      : today
                          ? palette.accent
                          : palette.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 5,
              child: marked
                  ? Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white.withValues(alpha: 0.85)
                            : palette.accent.withValues(alpha: 0.7),
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

class _ThreeDayCell extends StatelessWidget {
  const _ThreeDayCell({
    required this.date,
    required this.selected,
    required this.marked,
    required this.weekday,
    required this.palette,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool marked;
  final String weekday;
  final CalendarPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Text(
            weekday,
            style: TextStyle(fontSize: 12, color: palette.textSecondary),
          ),
          const SizedBox(height: 6),
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? palette.accent : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 5,
            child: marked
                ? Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
