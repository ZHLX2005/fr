import 'package:flutter/material.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/event.dart';
import '../domain/next_birthday.dart';
import '../lunar_adapter.dart';
import 'person_form_sheet.dart';

/// 人物详情页
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
        final events = cal.events.where((e) => e.personId == personId).toList();
        final birthday = events
            .where((e) => e.type == EventType.birthday)
            .cast<Event?>()
            .firstWhere((_) => true, orElse: () => null);
        final today = DateTime.now();
        final resolver = NextBirthdayResolver(LunarAdapter());
        final next = birthday == null ? null : resolver.upcoming(birthday, today);
        // age 委托 provider：内部已按 system 区分（lunar 用出生公历日换算）
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
                // SoT：显示存储的原值（已是该 system 历法下的值）+ 历法标签
                Builder(builder: (_) {
                  final leap = birthday.isLeap ? '闰' : '';
                  return Text(
                    birthday.system == CalendarSystem.solar
                        ? '公历 ${birthday.year} 年 ${birthday.month} 月 ${birthday.day} 日'
                        : '农历 ${birthday.year} 年 $leap${birthday.month} 月 ${birthday.day}',
                    style: AppText.body(),
                  );
                }),
                const SizedBox(height: 4),
                // 对方历法等值（双向）
                Builder(builder: (_) {
                  if (birthday.system == CalendarSystem.solar) {
                    final l = LunarAdapter().fromSolar(
                      DateTime(birthday.year, birthday.month, birthday.day),
                    );
                    return Text(
                      '≈ 农历 ${l.year} 年 ${l.isLeap ? "闰" : ""}${l.month} 月 ${l.day}',
                      style: AppText.caption(color: pp.inkMuted),
                    );
                  } else {
                    final anchor = birthday.lunarAnchorYear ?? birthday.year;
                    final s = LunarAdapter().toSolar(
                      anchor,
                      birthday.month,
                      birthday.day,
                      isLeap: birthday.isLeap,
                    );
                    return Text(
                      '≈ 公历 ${s.year} 年 ${s.month} 月 ${s.day}',
                      style: AppText.caption(color: pp.inkMuted),
                    );
                  }
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
    final linkedEvents = cal.events.where((e) => e.personId == personId).toList();
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
    // 级联删除关联事件
    for (final e in linkedEvents) {
      await cal.remove(e.id);
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
    return Material(
      color: pp.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: pp.today, width: 1.5),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppText.body().copyWith(
              color: pp.today,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}