import 'package:flutter/material.dart';

import '../../core/focus/focus_timer_page.dart';
import '../lab_container.dart';

/// 番茄钟：专注计时 + 统计（心流空间全屏计时页）。
///
/// 原 Time 核心容器（core-time/FocusHomePage）退役后（fr 33），番茄钟以
/// Lab demo 身份独立存在；`fr://lab/core/focus` 深链同义直达计时页。
class FocusDemo extends DemoPage {
  @override
  String get title => '番茄钟';

  @override
  String get slug => 'focus';

  @override
  String get description => '专注计时 · 心流空间 · 每日统计';

  @override
  bool get preferFullScreen => true;

  /// 无专属 SVG（图标集 53 张已用尽），底栏/钉选网格回退 Material 图标。
  @override
  IconData? get navIcon => Icons.timer_outlined;

  @override
  Widget buildPage(BuildContext context) {
    return const FocusTimerPage();
  }
}

void registerFocusDemo() {
  demoRegistry.register(FocusDemo());
}
