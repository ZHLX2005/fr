import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/lab_calendar_provider.dart';
import '../../data/lab_people_provider.dart';
import '../../domain/person.dart';
import 'day_cell.dart';

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
        final events = cal.events
            .where((e) => e.month == date.month && e.day == date.day)
            .toList();
        final evPeople = <Person>[
          for (final e in events)
            if (e.personId != null)
              if (people.byId(e.personId!) != null) people.byId(e.personId!)!,
        ];
        return DayCell(
          date: date,
          inCurrentMonth: inMonth,
          isToday: isToday,
          events: events,
          people: evPeople,
          onTap: inMonth ? () => onDayTap(date) : null,
          onLongPress: inMonth ? () => onDayLongPress(date) : null,
        );
      },
    );
  }
}