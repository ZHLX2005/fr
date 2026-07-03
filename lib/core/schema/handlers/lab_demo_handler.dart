import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/lab/lab_container.dart';
import '../fr_route_handler.dart';

/// fr://lab/demo/{demoKey} → DemoPage
///
/// demoKey 是 demoRegistry 注册时的 title（保留 demoRegistry 作为查询源）。
class LabDemoHandler extends FrRouteHandler {
  const LabDemoHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final demoKey = match.path;  // 整段 path 即可，因为 host 已经限定 lab/demo
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