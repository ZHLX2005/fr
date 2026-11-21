import 'package:flutter/material.dart';

import '../../core/timetable/presentation/timetable_page.dart';
import '../lab_container.dart';

/// 时间课表：循环周课程表（多空间 · 追剧模式 · 桌面小组件）。
///
/// 原 Time 核心容器退役后（fr 33）从容器内页改为 Lab demo 独立入口；
/// `fr://lab/core/timetable` 深链保持直达（lab_core_handler）。
class TimetableDemo extends DemoPage {
  @override
  String get title => '课程表';

  @override
  String get slug => 'timetable';

  @override
  String get description => '循环周课表 · 多空间 · 追剧模式 · 桌面小组件';

  @override
  bool get preferFullScreen => true;

  /// 专属 SVG = 54-timetable（fr #38 补绘）；navIcon 仅作 SVG 加载失败的兜底。
  @override
  IconData? get navIcon => Icons.calendar_month_outlined;

  @override
  Widget buildPage(BuildContext context) {
    return const TimetablePage();
  }
}

void registerTimetableDemo() {
  demoRegistry.register(TimetableDemo());
}
