import 'package:flutter/material.dart';
import '../../../../widgets/context_colors.dart';

import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';

/// 年度事件报表
class AnnualReportPage extends StatelessWidget {
  final LabCalendarProvider cal;
  final LabPeopleProvider people;
  AnnualReportPage({super.key, required this.cal, required this.people});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([cal, people]),
      builder: (context, _) {
        final birthdays =
            cal.events.where((e) => e.type == EventType.birthday).toList();
        return ListView(
          padding: EdgeInsets.all(20),
          children: [
            Text(
              '${cal.viewYear} 年度报表',
              style: TextStyle(
                color: context.colors.text,
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            SizedBox(height: 8),
            Text('共 ${birthdays.length} 个生日', style: AppText.body()),
            SizedBox(height: 24),
            ...List.generate(12, (i) => i + 1).map((m) {
              // 按事件在 viewYear 的公历发生日分组（lunar 事件先 resolve 到公历）
              final mEvents = cal.events
                  .map((e) => (e: e, d: cal.solarOccurrenceInYear(e, cal.viewYear)))
                  .where((p) => p.d != null && p.d!.month == m)
                  .toList();
              return Container(
                margin: EdgeInsets.only(bottom: 12),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: context.colors.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$m 月',
                      style: TextStyle(
                        color: context.colors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    if (mEvents.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('—', style: AppText.caption()),
                      )
                    else
                      ...mEvents.map((p) {
                        final person = p.e.personId == null
                            ? null
                            : people.byId(p.e.personId!);
                        return Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            '${p.d!.day}日 · ${p.e.title}${person == null ? "" : "（${person.name}）"}',
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