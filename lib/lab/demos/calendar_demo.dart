import 'package:flutter/material.dart';

import '../lab_container.dart';

/// 日历待办 Demo —— 占位页
///
/// 原有 5 视图 / 农历 / DSL / 联系人 / 桌面小组件等实现已清空，等待重新设计。
/// slug 保持 'calendar' 以兼容 `fr://lab/demo/calendar` 路由与 Focus 主页入口。
class CalendarDemo extends DemoPage {
  @override
  String get title => '日历待办';

  @override
  String get slug => 'calendar';

  @override
  String get description => '日历待办 - 待重构';

  @override
  bool get preferFullScreen => true;

  @override
  bool get timePage => true;

  @override
  Widget buildPage(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('日历待办 - 占位'),
      ),
    );
  }
}

void registerCalendarDemo() {
  demoRegistry.register(CalendarDemo());
}