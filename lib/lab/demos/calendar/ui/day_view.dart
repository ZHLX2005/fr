import 'package:flutter/material.dart';

import '../../../../core/theme/component/calendar/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../domain/anchor.dart';
import '../domain/event.dart';
import '../domain/event_occurrence.dart';

/// 日视图（今日）
class DayView extends StatelessWidget {
  final LabCalendarProvider cal;
  const DayView({super.key, required this.cal});

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return AnimatedBuilder(
      animation: cal,
      builder: (context, _) {
        final today = DateTime.now();
        final occs = cal.eventsOn(today);
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${today.year}年${today.month}月${today.day}日',
              style: TextStyle(
                color: pp.ink,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            if (occs.isEmpty)
              Text('今天没有事件', style: AppText.body(color: pp.inkMuted))
            else
              ...occs.map(
                (o) => ListTile(
                  title: Text(o.event.title, style: AppText.body()),
                  subtitle: Text(
                    '${_typeNameOf(o.event.type)} · ${o.event.anchor is SolarAnchor ? "公历" : "农历"}',
                    style: AppText.caption(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _typeNameOf(EventType t) {
  switch (t) {
    case EventType.birthday:
      return '生日';
    case EventType.anniversary:
      return '纪念日';
    case EventType.countdown:
      return '倒计时';
    case EventType.holiday:
      return '节日';
    case EventType.task:
      return '待办';
    case EventType.custom:
      return '自定义';
  }
}