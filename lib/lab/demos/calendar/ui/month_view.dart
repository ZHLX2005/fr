import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/paper_palette.dart';
import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';
import 'widgets/month_grid.dart';

/// 月视图主页面
class MonthView extends StatelessWidget {
  final void Function(DateTime) onDayTap;
  final void Function(DateTime) onDayLongPress;
  const MonthView({
    super.key,
    required this.onDayTap,
    required this.onDayLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    return Column(
      children: [
        MonthHeader(
          year: p.viewYear,
          month: p.viewMonth,
          isOnCurrentMonth: p.isOnCurrentMonth,
          onPrev: p.prevMonth,
          onNext: p.nextMonth,
          onJumpToday: p.jumpToday,
        ),
        const _WeekdayHeader(),
        const SizedBox(height: 8),
        Expanded(
          child: MonthGrid(
            year: p.viewYear,
            month: p.viewMonth,
            onDayTap: onDayTap,
            onDayLongPress: onDayLongPress,
          ),
        ),
      ],
    );
  }
}

/// 月视图头部：年月标题（点击跳今天）+ 前后翻页箭头 + 条件"今天"药丸。
/// 抽出为独立 widget：一是避免 MonthView 内嵌逻辑难以测试，二是让
/// "非当前月时显示药丸"的 UI 可被 widget 测试覆盖（无 LunarLabel/GoogleFonts）。
class MonthHeader extends StatelessWidget {
  final int year;
  final int month;
  final bool isOnCurrentMonth;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onJumpToday;

  const MonthHeader({
    super.key,
    required this.year,
    required this.month,
    required this.isOnCurrentMonth,
    this.onPrev,
    this.onNext,
    this.onJumpToday,
  });

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            color: pp.ink,
            onPressed: onPrev,
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: onJumpToday,
                    child: Text(
                      '$year年$month月',
                      style: TextStyle(
                        color: pp.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (!isOnCurrentMonth) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onJumpToday,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: pp.today,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '今天',
                          style: TextStyle(
                            color: pp.today,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            color: pp.ink,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final pp = PaperPalette.of(context);
    const days = ['日', '一', '二', '三', '四', '五', '六'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: days
            .asMap()
            .entries
            .map(
              (e) => Expanded(
                child: Center(
                  child: Text(
                    e.value,
                    style: AppText.caption(
                      color: (e.key == 0 || e.key == 6)
                          ? pp.inkMuted
                          : pp.inkFaint,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
