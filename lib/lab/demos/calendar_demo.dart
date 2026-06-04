import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../lab_container.dart';
import 'calendar/providers/lab_calendar_provider.dart';
import 'calendar/calendar_month_grid.dart';

/// 日历待办 Demo
///
/// - 单月 7×6 网格，每天是一个圆
/// - 当天的多个待办用各自颜色等分弧描边
/// - 点击日期 → 底部抽屉管理事件
/// - 同步桌面 widget（CalendarWidgetProvider）
class CalendarDemo extends DemoPage {
  @override
  String get title => '日历待办';

  @override
  String get description => '圆环色弧标记每日待办，可桌面 widget';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const _CalendarDemoPage();
}

class _CalendarDemoPage extends StatelessWidget {
  const _CalendarDemoPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          '日历待办',
          style: TextStyle(
            color: Color(0xFF000000),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: const SafeArea(
        child: Column(
          children: [
            _MonthHeader(),
            SizedBox(height: 8),
            _WeekdayHeader(),
            Expanded(child: CalendarMonthGrid()),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader();

  @override
  Widget build(BuildContext context) {
    return Consumer<LabCalendarProvider>(
      builder: (context, p, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                color: const Color(0xFF333333),
                onPressed: p.prevMonth,
                tooltip: '上一月',
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: p.jumpToday,
                    child: Text(
                      '${p.viewYear}年${p.viewMonth}月',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF000000),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                color: const Color(0xFF333333),
                onPressed: p.nextMonth,
                tooltip: '下一月',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    const weekdays = ['日', '一', '二', '三', '四', '五', '六'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: weekdays
            .asMap()
            .entries
            .map(
              (e) => Expanded(
                child: Center(
                  child: Text(
                    e.value,
                    style: TextStyle(
                      fontSize: 12,
                      color: (e.key == 0 || e.key == 6)
                          ? const Color(0xFFE57373)
                          : const Color(0xFF999999),
                      fontWeight: FontWeight.w500,
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

void registerCalendarDemo() {
  demoRegistry.register(CalendarDemo());
}
