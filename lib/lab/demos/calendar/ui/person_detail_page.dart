import 'package:flutter/material.dart';

import '../../../../core/theme/component/calendar/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/anchor.dart';
import '../domain/event.dart';
import '../domain/next_birthday.dart';
import '../lunar_adapter.dart';
import 'person_form_sheet.dart';

/// 人物详情页（v2：用 Anchor 替代 system/year/month/day）
class PersonDetailPage extends StatelessWidget {
  final String personId;
  final LabCalendarProvider cal;
  final LabPeopleProvider people;
  const PersonDetailPage({
    super.key,
    required this.personId,
    required this.cal,
    required this.people,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([cal, people]),
      builder: (context, _) {
        final person = people.byId(personId);
        if (person == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('人已被删除')),
          );
        }
        final events = cal.events
            .where((e) => e.people.any((p) => p.name == person.name))
            .toList();
        final birthday = events
            .where((e) => e.type == EventType.birthday)
            .cast<Event?>()
            .firstWhere((_) => true, orElse: () => null);
        final today = DateTime.now();
        final resolver = NextBirthdayResolver(LunarAdapter());
        final next = birthday == null ? null : resolver.upcoming(birthday, today);
        final age = birthday == null
            ? null
            : cal.ageOfBirthdayPerson(birthday, today);

        return Scaffold(
          backgroundColor: pp.bg,
          appBar: AppBar(
            backgroundColor: pp.bg,
            elevation: 0,
            title: Text(person.name, style: AppText.title()),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PersonFormSheet(
                      existing: person,
                      cal: cal,
                      people: people,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                color: pp.today,
                onPressed: () => _confirmDelete(context),
                tooltip: '删除',
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Text(
                  person.name.isEmpty ? '👤' : person.name.substring(0, 1),
                  style: const TextStyle(fontSize: 72),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text(person.name, style: AppText.display())),
              Center(
                  child: Text(person.relation.name, style: AppText.caption())),
              const SizedBox(height: 24),
              if (birthday != null && next != null) ...[
                Text('生日', style: AppText.title()),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final a = birthday.anchor;
                  if (a is SolarAnchor) {
                    return Text(
                      '公历 ${a.year} 年 ${a.month} 月 ${a.day} 日',
                      style: AppText.body(),
                    );
                  } else if (a is LunarAnchor) {
                    final leap = a.isLeap ? '闰' : '';
                    return Text(
                      '农历 ${a.year} 年 $leap${a.month} 月 ${a.day} 日',
                      style: AppText.body(),
                    );
                  }
                  return const SizedBox();
                }),
                const SizedBox(height: 4),
                Builder(builder: (_) {
                  final a = birthday.anchor;
                  if (a is SolarAnchor) {
                    final l = LunarAdapter().fromSolar(
                      DateTime(a.year, a.month, a.day),
                    );
                    return Text(
                      '≈ 农历 ${l.year} 年 ${l.isLeap ? "闰" : ""}${l.month} 月 ${l.day}',
                      style: AppText.caption(color: pp.inkMuted),
                    );
                  } else if (a is LunarAnchor) {
                    final s = LunarAdapter().toSolar(
                      a.year, a.month, a.day, isLeap: a.isLeap,
                    );
                    return Text(
                      '≈ 公历 ${s.year} 年 ${s.month} 月 ${s.day}',
                      style: AppText.caption(color: pp.inkMuted),
                    );
                  }
                  return const SizedBox();
                }),
                const SizedBox(height: 4),
                Text(
                  '下次生日：${next.year}年${next.month}月${next.day}日 · 距今 ${NextBirthdayResolver.daysUntil(next, today)} 天',
                  style: AppText.caption(),
                ),
                if (age != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$age 岁', style: AppText.caption()),
                  ),
              ],
              const SizedBox(height: 24),
              Text('备注', style: AppText.title()),
              Text(person.note ?? '—', style: AppText.body()),
              const SizedBox(height: 32),
              PaperDangerButton(
                label: '删除此人',
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final pp = PaperPalette.of(context);
    final person = people.byId(personId);
    if (person == null) return;
    final linkedEvents = cal.events
        .where((e) => e.people.any((p) => p.name == person.name))
        .toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: pp.bgElevated,
        title: Text('删除人物', style: AppText.title()),
        content: Text(
          '确定要删除"${person.name}"？\n\n将一并删除 ${linkedEvents.length} 个关联事件。',
          style: AppText.body(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: pp.today),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    for (final e in linkedEvents) {
      await cal.removeEvent(e.id);
    }
    await people.remove(personId);
    if (context.mounted) Navigator.pop(context);
  }
}

/// 纸张风格危险按钮（边框强调 + 朱砂红）
class PaperDangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const PaperDangerButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: pp.today,
        side: BorderSide(color: pp.today, width: 1.5),
      ),
      icon: const Icon(Icons.delete_outline, size: 18),
      label: Text(label),
    );
  }
}