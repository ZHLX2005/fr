import 'package:flutter/material.dart';

import '../../core/calendar/presentation/calendar_page.dart';
import '../lab_container.dart';

/// 日历待办：仿滴答清单的月/周/日视图，任务存 SQLite。
///
/// slug 保持 'calendar' 以兼容 `fr://lab/demo/calendar` 路由与 Focus 主页入口。
class CalendarDemo extends DemoPage {
  @override
  String get title => '日历';

  @override
  String get slug => 'calendar';

  @override
  String get description => '月/周/日视图 · 拖拽折叠 · SQLite 任务';

  @override
  bool get preferFullScreen => true;

  @override
  bool get timePage => true;

  @override
  Widget buildPage(BuildContext context) {
    return const CalendarPage();
  }
}

void registerCalendarDemo() {
  demoRegistry.register(CalendarDemo());
}
