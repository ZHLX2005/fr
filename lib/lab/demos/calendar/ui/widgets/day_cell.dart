import 'package:flutter/material.dart';

import '../../../../../core/theme/paper_palette.dart';
import '../../../../../core/theme/typography.dart';
import '../../domain/event.dart';
import '../../domain/person.dart';
import 'lunar_label.dart';
import 'person_chip.dart';

/// 单日 cell：
/// - 当天：朱砂红数字 + 1px 朱砂外圈（不填充，去塑料感）
/// - 周末/邻月：墨黑/雾墨
/// - 农历小字 + 头像堆叠 + +N
class DayCell extends StatelessWidget {
  final DateTime date;
  final bool inCurrentMonth;
  final bool isToday;
  final List<Event> events;
  final List<Person> people; // 关联人（取自 provider）
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const DayCell({
    super.key,
    required this.date,
    required this.inCurrentMonth,
    required this.isToday,
    required this.events,
    this.people = const [],
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final Color numberColor;
    if (isToday) {
      numberColor = PaperPalette.today;
    } else if (!inCurrentMonth) {
      numberColor = PaperPalette.inkFaint;
    } else {
      numberColor = PaperPalette.ink;
    }

    final hasBirthday = events.any((e) => e.type == EventType.birthday);
    final has = people.take(3).toList();
    final overflow = people.length - has.length;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          border: isToday
              ? Border.all(color: PaperPalette.today, width: 1)
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${date.day}',
                    style: AppText.title(color: numberColor).copyWith(fontSize: 17),
                  ),
                  if (inCurrentMonth)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: LunarLabel(solar: date),
                    ),
                ],
              ),
            ),
            // 生日黄土点贴角
            if (hasBirthday && inCurrentMonth)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: PaperPalette.highlight,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            // 头像堆叠
            if (has.isNotEmpty && inCurrentMonth)
              Positioned(
                bottom: 3,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...has.map(
                      (p) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: PersonChip(person: p, size: 10),
                      ),
                    ),
                    if (overflow > 0)
                      Text('+$overflow', style: AppText.caption()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}