import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/lab_calendar_event.dart';
import 'providers/lab_calendar_provider.dart';
import 'calendar_day_cell.dart';
import 'calendar_day_sheet.dart';

/// 月历 7×6 网格
class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LabCalendarProvider>(
      builder: (context, p, _) {
        final today = DateTime.now();
        final firstOfMonth = DateTime(p.viewYear, p.viewMonth, 1);
        final firstDow = firstOfMonth.weekday % 7; // Sun=0
        final daysInMonth = DateTime(p.viewYear, p.viewMonth + 1, 0).day;
        final prevMonthDays = DateTime(p.viewYear, p.viewMonth, 0).day;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemCount: 42,
            itemBuilder: (_, idx) {
              int displayDay;
              bool inCurrentMonth;
              if (idx < firstDow) {
                displayDay = prevMonthDays - (firstDow - idx - 1);
                inCurrentMonth = false;
              } else if (idx >= firstDow + daysInMonth) {
                displayDay = idx - firstDow - daysInMonth + 1;
                inCurrentMonth = false;
              } else {
                displayDay = idx - firstDow + 1;
                inCurrentMonth = true;
              }
              final isToday = inCurrentMonth &&
                  p.viewYear == today.year &&
                  p.viewMonth == today.month &&
                  displayDay == today.day;
              final col = idx % 7;
              final isWeekend = col == 0 || col == 6;

              final events = inCurrentMonth
                  ? p.eventsOf(p.viewYear, p.viewMonth, displayDay)
                  : const <LabCalendarEvent>[];

              return CalendarDayCell(
                day: displayDay,
                isToday: isToday,
                inCurrentMonth: inCurrentMonth,
                isWeekend: isWeekend,
                colors: events.map((e) => e.color).toList(),
                onTap: inCurrentMonth
                    ? () => _openDayEditor(
                          context,
                          p.viewYear,
                          p.viewMonth,
                          displayDay,
                        )
                    : null,
              );
            },
          ),
        );
      },
    );
  }

  void _openDayEditor(BuildContext context, int year, int month, int day) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CalendarDayEventSheet(year: year, month: month, day: day),
    );
  }
}
