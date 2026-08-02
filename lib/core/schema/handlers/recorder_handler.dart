import 'package:flutter/material.dart';

import '../fr_route_handler.dart';
import '../../../lab/demos/recorder/recorder_page.dart'
    show RecorderDemoPage;
import '../../../lab/demos/recorder/recorder_demo.dart'
    show markRecorderAutoStart;

/// fr://lab/demo/recorder?autostart={true|false} → 录音机 Demo
///
/// 与 LabDemoHandler 的关系:
///   - LabDemoHandler 是通用 `lab/demo/{slug}` 入口,直接 _DemoDetailPage(demo: ...)
///   - 这里走的是「专用 handler」:`lab/demo/recorder` 命中后,**除了**显示页面,
///     还要按 `?autostart=true` 触发立即录音(桌面 widget 点击场景)。
///
/// 与 NotionImageHostHandler 同样的模式:router 阶段 prefix 匹配到 'lab/demo',
/// 我们用更严格的 authority 验证 + query 取 autostart。
/// 详细 SOP:references/Flutter-fr路由-注册规范与防腐蚀.md。
class RecorderHandler extends FrRouteHandler {
  const RecorderHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    assert(
      match.authority == 'lab/demo/recorder',
      'RecorderHandler 期望 authority=lab/demo/recorder,实际: ${match.authority}',
    );
    final autostart = match.queryBool('autostart');
    return _RecorderDeepLinkPage(autostart: autostart);
  }
}

/// Recorder 桌面小组件入口页:包装 RecorderDemoPage,按 autostart
/// 标志触发自动开始录音。仅当 autostart=true(桌面 widget 点击进入)时
/// 才走 markRecorderAutoStart(),让 RecorderDemoPage mount 后消费 flag。
class _RecorderDeepLinkPage extends StatelessWidget {
  final bool autostart;
  const _RecorderDeepLinkPage({required this.autostart});

  @override
  Widget build(BuildContext context) {
    if (autostart) {
      // 同步标记 pending —— RecorderDemoPage.didChangeDependencies 会消费它。
      // 不要在此处直接 await controller.start(),因为 RecorderDemoPage 还在
      // 构造中,controller 尚未 attach。
      markRecorderAutoStart();
    }
    return const RecorderDemoPage();
  }
}