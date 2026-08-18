import 'package:flutter/material.dart';
import '../../../../widgets/context_colors.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/typography.dart';
import '../data/lab_calendar_provider.dart';

/// 年视图（3×4 月份小卡）
class YearView extends StatelessWidget {
  final void Function(int month) onMonthTap;
  YearView({super.key, required this.onMonthTap});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<LabCalendarProvider>();
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.9,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      padding: EdgeInsets.all(16),
      itemCount: 12,
      itemBuilder: (_, i) {
        final m = i + 1;
        final events = p.events
            .where((e) {
              final d = p.solarOccurrenceInYear(e, p.viewYear);
              return d != null && d.month == m;
            })
            .length;
        return GestureDetector(
          onTap: () => onMonthTap(m),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: context.colors.outline, width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.all(12),
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
                Spacer(),
                Text('$events 个事件', style: AppText.caption()),
              ],
            ),
          ),
        );
      },
    );
  }
}