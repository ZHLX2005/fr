import 'package:flutter/material.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';

/// 年度事件报表
class AnnualReportPage extends StatelessWidget {
  final LabCalendarProvider cal;
  final LabPeopleProvider people;
  const AnnualReportPage({super.key, required this.cal, required this.people});

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([cal, people]),
      builder: (context, _) {
        final birthdays =
            cal.events.where((e) => e.type == EventType.birthday).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${cal.viewYear} 年度报表',
              style: TextStyle(
                color: pp.ink,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text('共 ${birthdays.length} 个生日', style: AppText.body()),
            const SizedBox(height: 24),
            ...List.generate(12, (i) => i + 1).map((m) {
              // 按事件在 viewYear 的公历发生日分组（lunar 事件先 resolve 到公历）
              final mEvents = cal.occurrencesBetween(
                DateTime(cal.viewYear, m, 1),
                DateTime(cal.viewYear, m + 1, 0, 23, 59, 59),
              );
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: pp.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$m 月',
                      style: TextStyle(
                        color: pp.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (mEvents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('—', style: AppText.caption()),
                      )
                    else
                      ...mEvents.map((o) {
                        final personName = o.event.people.isNotEmpty
                            ? o.event.people.first.name
                            : null;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${o.date.day}日 · ${o.event.title}${personName == null ? "" : "（$personName）"}',
                            style: AppText.caption(),
                          ),
                        );
                      }),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}