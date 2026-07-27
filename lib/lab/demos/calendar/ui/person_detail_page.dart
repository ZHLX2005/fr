import 'package:flutter/material.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import '../data/lab_people_provider.dart';
import '../domain/age_calculator.dart';
import '../domain/event.dart';
import '../domain/next_birthday.dart';
import '../lunar_adapter.dart';
import 'person_form_sheet.dart';
import 'widgets/paper_button.dart';

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
        final age = birthday == null
            ? null
            : AgeCalculator.calculate(
                DateTime(today.year, birthday.month, birthday.day),
                today,
              );

        return Scaffold(
          backgroundColor: PaperPalette.bg,
          appBar: AppBar(
            backgroundColor: PaperPalette.bg,
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
                color: PaperPalette.today,
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
                Text(
                  '${next.year}年${next.month}月${next.day}日 · 距今 ${NextBirthdayResolver.daysUntil(next, today)} 天',
                  style: AppText.body(),
                ),
                if (age != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$age 岁', style: AppText.caption()),
                  ),
                if (birthday.system == CalendarSystem.solar)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Builder(builder: (_) {
                      final l = LunarAdapter().fromSolar(
                        DateTime(today.year, birthday.month, birthday.day),
                      );
                      return Text(
                        '每年农历 ${l.month} 月 ${l.day} 日',
                        style: AppText.caption(color: PaperPalette.inkMuted),
                      );
                    }),
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
    final person = people.byId(personId);
    if (person == null) return;
    final linkedEvents = cal.events.where((e) => e.personId == personId).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: PaperPalette.bgElevated,
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
            style: TextButton.styleFrom(foregroundColor: PaperPalette.today),
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
    return Material(
      color: PaperPalette.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: PaperPalette.today, width: 1.5),
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
              color: PaperPalette.today,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}