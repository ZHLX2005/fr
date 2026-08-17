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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                color: PaperPalette.ink,
                onPressed: p.prevMonth,
              ),
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: p.jumpToday,
                        child: Text(
                          '${p.viewYear}年${p.viewMonth}月',
                          style: const TextStyle(
                            color: PaperPalette.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                      if (!p.isOnCurrentMonth) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: p.jumpToday,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: PaperPalette.today,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '今天',
                              style: TextStyle(
                                color: PaperPalette.today,
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
                color: PaperPalette.ink,
                onPressed: p.nextMonth,
              ),
            ],
          ),
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

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
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
                          ? PaperPalette.inkMuted
                          : PaperPalette.inkFaint,
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