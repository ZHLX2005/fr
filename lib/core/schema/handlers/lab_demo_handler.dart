import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/lab/lab_container.dart';
import '../fr_route_handler.dart';

/// fr://lab/demo/{demoKey} → DemoPage
///
/// Router 阶段：authority 'lab/demo/...' 前缀匹配到 'lab/demo'。
/// Handler 从 authority 尾段切 demoKey：authority='lab/demo/clock' → demoKey='clock'。
/// demoKey 是 demoRegistry 注册时的 title（保留 demoRegistry 作为查询源）。
class LabDemoHandler extends FrRouteHandler {
  static const _prefix = 'lab/demo/';

  const LabDemoHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final auth = match.authority;
    if (!auth.startsWith(_prefix) || auth == _prefix.substring(0, _prefix.length - 1)) {
      return _NotFoundPage(message: '非法 lab demo 路由: $auth');
    }
    final demoKey = auth.substring(_prefix.length);
    final demo = demoRegistry.get(demoKey);
    if (demo == null) {
      return _NotFoundPage(message: '未找到 Demo: $demoKey');
    }
    return _DemoDetailPage(demo: demo);
  }
}

class _DemoDetailPage extends StatelessWidget {
  final DemoPage demo;
  const _DemoDetailPage({required this.demo});

  @override
  Widget build(BuildContext context) {
    return demo.buildPage(context);
  }
}

class _NotFoundPage extends StatelessWidget {
  final String message;
  const _NotFoundPage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('未找到')),
      body: Center(child: Text(message)),
    );
  }
}
