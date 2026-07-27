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
    return AnimatedBuilder(
      animation: Listenable.merge([cal, people]),
      builder: (context, _) {
        final birthdays =
            cal.events.where((e) => e.type == EventType.birthday).toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${cal.viewYear} 年度报表', style: AppText.display()),
            const SizedBox(height: 8),
            Text('共 ${birthdays.length} 个生日', style: AppText.body()),
            const SizedBox(height: 24),
            ...List.generate(12, (i) => i + 1).map((m) {
              final mEvents = cal.events.where((e) => e.month == m).toList();
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: PaperPalette.line),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$m 月', style: AppText.title()),
                    if (mEvents.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('—', style: AppText.caption()),
                      )
                    else
                      ...mEvents.map((e) {
                        final person = e.personId == null
                            ? null
                            : people.byId(e.personId!);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${e.day}日 · ${e.title}${person == null ? "" : "（${person.name}）"}',
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