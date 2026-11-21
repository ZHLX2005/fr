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

  /// 专属 SVG = 55-pomodoro（fr #38 补绘）；navIcon 仅作 SVG 加载失败的兜底。
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
