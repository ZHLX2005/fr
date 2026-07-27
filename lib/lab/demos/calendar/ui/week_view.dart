import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';

/// 周视图
class WeekView extends StatelessWidget {
  final void Function(DateTime) onDayTap;
  const WeekView({super.key, required this.onDayTap});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    final today = DateTime.now();
    final weekStart = today.subtract(Duration(days: today.weekday % 7));
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return ListView(
      children: days.map((d) {
        final events = p.events
            .where((e) => e.month == d.month && e.day == d.day)
            .toList();
        final isToday = d.year == today.year &&
            d.month == today.month &&
            d.day == today.day;
        return ListTile(
          leading: Text(
            '${d.month}/${d.day}',
            style: AppText.body().copyWith(
              color: isToday ? PaperPalette.today : PaperPalette.ink,
              fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          title: Text(
            events.isEmpty
                ? '无事件'
                : events.map((e) => e.title).join(' · '),
            style: AppText.caption(),
          ),
          onTap: () => onDayTap(d),
        );
      }).toList(),
    );
  }
}