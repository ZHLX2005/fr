import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/lab_calendar_provider.dart';
import '../../data/lab_people_provider.dart';
import '../../domain/person.dart';
import 'day_cell.dart';

/// '#C8553D' → Color(0xFFC8553D)
Color _hexToColor(String hex) =>
    Color(int.parse('FF${hex.substring(1)}', radix: 16));

class MonthGrid extends StatelessWidget {
  final int year;
  final int month;
  final void Function(DateTime) onDayTap;
  final void Function(DateTime) onDayLongPress;

  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.onDayTap,
    required this.onDayLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cal = context.watch<LabCalendarProvider>();
    final people = context.watch<LabPeopleProvider>();

    final first = DateTime(year, month, 1);
    final firstDow = first.weekday % 7; // Sun=0
    final days = DateTime(year, month + 1, 0).day;
    final prevDays = DateTime(year, month, 0).day;
    final today = DateTime.now();

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: 42,
      itemBuilder: (_, i) {
        DateTime date;
        bool inMonth = true;
        if (i < firstDow) {
          date = DateTime(year, month - 1, prevDays - (firstDow - i - 1));
          inMonth = false;
        } else if (i >= firstDow + days) {
          date = DateTime(year, month + 1, i - firstDow - days + 1);
          inMonth = false;
        } else {
          date = DateTime(year, month, i - firstDow + 1);
        }
        final isToday = date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;
        final events = cal.eventsOn(date);
        final evPeople = <Person>[
          for (final o in events)
            if (o.event.people.isNotEmpty && o.event.people.first.name != null)
              if (people.byNameAnyGroup(o.event.people.first.name!) != null)
                people.byNameAnyGroup(o.event.people.first.name!)!,
        ];
        // 当天所有事件的 colorTag 去重（保持插入顺序）→ 彩色小圆点
        final seen = <String>{};
        final dotColors = <Color>[];
        for (final o in events) {
          if (seen.add(o.event.colorTag.name)) {
            dotColors.add(_hexToColor(o.event.colorTag.hex));
          }
        }
        return DayCell(
          date: date,
          inCurrentMonth: inMonth,
          isToday: isToday,
          events: events.map((o) => o.event).toList(),
          people: evPeople,
          eventDotColors: inMonth ? dotColors : const [],
          onTap: inMonth ? () => onDayTap(date) : null,
          onLongPress: inMonth ? () => onDayLongPress(date) : null,
        );
      },
    );
  }
}