import 'package:flutter/material.dart';

import '../domain/calendar_date_utils.dart';
import 'calendar_palette.dart';

/// 年视图：12 个迷你月历，点某一天直接进入该月。
class CalendarYearView extends StatelessWidget {
  const CalendarYearView({
    super.key,
    required this.year,
    required this.selectedDate,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.onDateSelected,
    required this.onYearChanged,
  });

  final int year;
  final DateTime selectedDate;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<int> onYearChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
          child: Row(
            children: [
              Text(
                '点选日期切换到月视图',
                style: TextStyle(
                  fontSize: 12,
                  color: palette.textSecondary.withValues(alpha: 0.9),
                ),
              ),
              const Spacer(),
              _YearArrow(
                icon: Icons.chevron_left,
                palette: palette,
                onTap: () => onYearChanged(year - 1),
              ),
              const SizedBox(width: 6),
              _YearArrow(
                icon: Icons.chevron_right,
                palette: palette,
                onTap: () => onYearChanged(year + 1),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: 12,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 158,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final month = DateTime(year, index + 1, 1);
              return _MiniMonthCard(
                month: month,
                selectedDate: selectedDate,
                markedDates: markedDates,
                mondayFirst: mondayFirst,
                palette: palette,
                onDateSelected: onDateSelected,
              );
            },
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
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: palette.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: palette.textSecondary),
      ),
    );
  }
}

class _MiniMonthCard extends StatelessWidget {
  const _MiniMonthCard({
    required this.month,
    required this.selectedDate,
    required this.markedDates,
    required this.mondayFirst,
    required this.palette,
    required this.onDateSelected,
  });

  final DateTime month;
  final DateTime selectedDate;
  final Set<String> markedDates;
  final bool mondayFirst;
  final CalendarPalette palette;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final gridStart = calendarMonthGridStart(month, mondayFirst: mondayFirst);
    final selectedMonth = selectedDate.year == month.year &&
        selectedDate.month == month.month;

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 7, 6, 5),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: palette.shadow.withValues(alpha: 0.55),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onDateSelected(DateTime(month.year, month.month, 1)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                '${month.month}月',
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: selectedMonth ? palette.accent : palette.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _MiniWeekdayRow(palette: palette),
          const SizedBox(height: 2),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 42,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.15,
                crossAxisSpacing: 0,
                mainAxisSpacing: 0,
              ),
              itemBuilder: (context, index) {
                final date = gridStart.add(Duration(days: index));
                final inMonth = date.month == month.month;
                final selected = calendarDateKey(date) ==
                    calendarDateKey(selectedDate);
                final marked = markedDates.contains(calendarDateKey(date));
                final dayColor = !inMonth
                    ? palette.textSecondary.withValues(alpha: 0.24)
                    : selected
                        ? Colors.white
                        : palette.textPrimary.withValues(alpha: 0.7);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onDateSelected(date),
                  child: Center(
                    child: Container(
                      width: 19,
                      height: 19,
                      alignment: Alignment.center,
                      decoration: selected
                          ? BoxDecoration(
                              color: palette.accent,
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Text(
                            '${date.day}',
                            style: TextStyle(
                              fontSize: 10,
                              height: 1,
                              color: dayColor,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                          if (marked && inMonth && !selected)
                            Positioned(
                              bottom: 0,
                              child: Container(
                                width: 2,
                                height: 2,
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniWeekdayRow extends StatelessWidget {
  const _MiniWeekdayRow({required this.palette});

  final CalendarPalette palette;

  @override
  Widget build(BuildContext context) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 7,
                  height: 1,
                  color: palette.textSecondary.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
