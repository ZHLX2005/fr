import 'package:flutter/material.dart';

import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import '../domain/next_birthday.dart';
import '../domain/person.dart';
import '../lunar_adapter.dart';
import 'person_detail_page.dart';
import 'person_form_sheet.dart';
import 'widgets/paper_button.dart';

/// 人视图（按关系分组 + 倒计时）
///
/// 用 AnimatedBuilder 监听 cal + people 两个 ChangeNotifier，
/// 任何一方变化（增删改事件/人）都触发重建。
class PeopleView extends StatelessWidget {
  final LabCalendarProvider cal;
  final LabPeopleProvider people;
  const PeopleView({super.key, required this.cal, required this.people});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([cal, people]),
      builder: (context, _) {
        final today = DateTime.now();
        final resolver = NextBirthdayResolver(LunarAdapter());

        final groups = <PersonRelation, List<Person>>{};
        for (final p in people.people) {
          groups.putIfAbsent(p.relation, () => []).add(p);
        }

        return ListView(
          padding: EdgeInsets.all(16),
          children: [
            for (final entry in groups.entries) ...[
              Text(entry.key.name, style: AppText.title()),
              SizedBox(height: 8),
              ...entry.value.map((p) {
                final birthday = cal.events
                    .where((e) => e.personId == p.id && e.type == EventType.birthday)
                    .cast<Event?>()
                    .firstWhere((_) => true, orElse: () => null);
                final next =
                    birthday == null ? null : resolver.upcoming(birthday, today);
                final days =
                    next == null ? null : NextBirthdayResolver.daysUntil(next, today);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Text(
                    (p.avatarEmoji != null && p.avatarEmoji!.isNotEmpty)
                        ? p.avatarEmoji!
                        : (p.name.isEmpty ? '👤' : p.name.substring(0, 1)),
                    style: const TextStyle(fontSize: 28),
                  ),
                  title: Text(p.name, style: AppText.body()),
                  subtitle: days == null
                      ? null
                      : Text('距生日 $days 天', style: AppText.caption()),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PersonDetailPage(
                        personId: p.id,
                        cal: cal,
                        people: people,
                      ),
                    ),
                  ),
                );
              }),
              SizedBox(height: 16),
            ],
            PaperPrimaryButton(
              icon: Icons.add_rounded,
              label: '新增人',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PersonFormSheet(cal: cal, people: people),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}