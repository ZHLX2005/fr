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
                  child: GestureDetector(
                    onTap: p.jumpToday,
                    child: Text(
                      '${p.viewYear}年${p.viewMonth}月',
                      style: AppText.title(),
                    ),
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