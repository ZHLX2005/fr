import 'package:flutter/material.dart';

import '../fr_route_handler.dart';

/// fr://notion/create-page?databaseId={id} → 创建 page（占位）
///
/// 真实创建逻辑在 LabDemo "Notion 图床" 里；handler 先返回 DemoPage 兜底。
class NotionCreatePageHandler extends FrRouteHandler {
  const NotionCreatePageHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    // 占位实现 — 真实功能尚未从 LabDemo 迁出
    return const _NotImplementedPage();
  }
}

class _NotImplementedPage extends StatelessWidget {
  const _NotImplementedPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('notion/create-page 尚未实现')),
    );
  }
}