import 'package:flutter/material.dart';

import '../fr_route_handler.dart';
import '../../../lab/demos/notion_image_host_demo.dart'
    show NotionImageHostPage, notionImageHostKey, triggerCaptureFromWidget;

/// fr://notion/image-host?autocapture={true|false} → Notion 图床 deep link
///
/// Router 阶段：authority 'notion/image-host' 整段匹配。
/// 防御性 guard：match.authority 必须严格等于 'notion/image-host'，避免误匹配
/// 'notion/image-host/extra' 之类的（当前没注册，但保留防御）。
///
/// Task 8: 用 NotionImageHostPage（来自 lab/demos/notion_image_host_demo.dart）
/// 替代 Task 7 的占位 widget。原 NotionImageHostDeepLinkPage 类从 main.dart
/// 整体搬到此处：保留 autocapture 语义 + 全局 GlobalKey + 延迟 300ms 触发拍照。
class NotionImageHostHandler extends FrRouteHandler {
  const NotionImageHostHandler();

  @override
  Widget build(BuildContext context, FrRouteMatch match) {
    assert(
      match.authority == 'notion/image-host',
      'NotionImageHostHandler 期望 authority=notion/image-host，实际: ${match.authority}',
    );
    final autocapture = match.queryBool('autocapture');
    return _NotionImageHostDeepLinkPage(autocapture: autocapture);
  }
}

/// Notion 图床桌面小组件入口页：包装 NotionImageHostPage，按 autocapture
/// 标志自动触发拍照。仅当 autocapture=true 时（桌面 widget 点击进入）才触发。
class _NotionImageHostDeepLinkPage extends StatelessWidget {
  final bool autocapture;

  const _NotionImageHostDeepLinkPage({required this.autocapture});

  @override
  Widget build(BuildContext context) {
    // 桌面 widget 入口：用全局 GlobalKey 跟踪
    final page = NotionImageHostPage(key: notionImageHostKey);
    if (autocapture) {
      // 等页面 mount + initState 跑完后再触发拍照。
      // _loadPrefs 内部用 SharedPreferences 是异步，所以多等 300ms。
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 300));
        triggerCaptureFromWidget();
      });
    }
    return page;
  }
}
