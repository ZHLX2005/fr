import 'package:flutter/material.dart';
import '../../../../../widgets/context_colors.dart';

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

  DayCell({
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
      numberColor = context.colors.danger;
    } else if (!inCurrentMonth) {
      numberColor = context.colors.scheme.outlineVariant;
    } else {
      numberColor = context.colors.text;
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
              ? Border.all(color: context.colors.danger, width: 1)
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
                    // 直接用默认字体（不套 Cormorant 等特殊衬线），与全 app 一致。
                    style: TextStyle(
                      color: numberColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (inCurrentMonth)
                    Padding(
                      padding: EdgeInsets.only(top: 1),
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
                  decoration: BoxDecoration(
                    color: context.colors.scheme.tertiary,
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
                        padding: EdgeInsets.symmetric(horizontal: 1),
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