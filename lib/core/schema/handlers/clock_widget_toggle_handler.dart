// lib/core/schema/handlers/clock_widget_toggle_handler.dart
import 'package:flutter/material.dart';

import '../fr_route_handler.dart';
import '../../../lab/demos/clock_demo.dart'
    show ClockDemoPage, markClockWidgetTogglePending;

/// fr://clock/widget-toggle → 时钟 demo 并自动 toggle 最新的 clock。
///
/// 桌面 widget 点击 toggle 按钮后：PendingIntent → MainActivity →
/// fr://clock/widget-toggle 路由 → 本 handler 返回包装页 →
/// `markClockWidgetTogglePending()` 标记 pending → ClockDemoPage.didChangeDependencies
/// 消费 flag → 调 LabClockProvider.toggleLatestClock()。
///
/// 与 RecorderHandler 同样的模式：专用 handler 在 router 阶段 prefix
/// 命中后，按 query/authority 验证 + 触发额外动作。
class ClockWidgetToggleHandler extends FrRouteHandler {
  const ClockWidgetToggleHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    assert(
      match.authority == 'clock/widget-toggle',
      'ClockWidgetToggleHandler 期望 authority=clock/widget-toggle,实际: ${match.authority}',
    );
    // 标记 pending —— ClockDemoPage mount 后消费。
    // 不要在此处直接调 toggleLatestClock(),因为 ClockDemoPage 还在构造中,
    // ChangeNotifierProvider 还没 attach。
    markClockWidgetTogglePending();
    return const ClockDemoPage();
  }
}