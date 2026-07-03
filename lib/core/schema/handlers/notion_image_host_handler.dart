import 'package:flutter/material.dart';

import '../fr_route_handler.dart';

/// fr://notion/image-host?autocapture={true|false} → Notion 图床 deep link
///
/// Task 7 阶段返回占位 Widget（保持 main.dart 不变、独立绿色 commit）。
/// Task 8 改 main.dart 时会把 `NotionImageHostDeepLinkPage` 整体从 main.dart
/// 搬到这里，handler 升级为真实引用。
class NotionImageHostHandler extends FrRouteHandler {
  const NotionImageHostHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    final autocapture = match.queryBool('autocapture');
    return _NotionImageHostPlaceholder(autocapture: autocapture);
  }
}

class _NotionImageHostPlaceholder extends StatelessWidget {
  final bool autocapture;
  const _NotionImageHostPlaceholder({required this.autocapture});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notion 图床')),
      body: Center(
        child: Text('autocapture=$autocapture (Task 8 接入真实页面)'),
      ),
    );
  }
}