import 'package:flutter/material.dart';

import 'fr_router.dart';
import 'fr_route_handler.dart';

/// fr:// 路由导航器（基于 frRouter 的 push 封装）
///
/// 替代原 SchemaNavigator，setNavigatorKey 接收 main.dart 的
/// GlobalKey<NavigatorState>，handle 调 frRouter.resolve + handler.build
/// 然后 push。
class FrNavigator {
  FrNavigator._();

  static GlobalKey<NavigatorState>? _navigatorKey;

  /// 设置全局 navigator key（main.dart 启动时调一次）
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// 入口：解析 URL + 找 handler + 错误 SnackBar + push
  static Future<void> handle(BuildContext? context, String url) async {
    final match = await frRouter.resolve(url);
    if (match == null) {
      // resolve 已 debugPrint 错误
      if (context != null && context.mounted) {
        _showError(context, '未知路由: $url');
      }
      return;
    }

    final handler = frRouter.findHandler(match.host);
    if (handler == null) return; // resolve 已处理

    Widget target;
    try {
      target = handler.build(context ?? _placeholderContext(), match);
    } catch (e, st) {
      debugPrint('FrNavigator: handler.build 抛异常: $e\n$st');
      if (context != null && context.mounted) {
        _showError(context, '路由 handler 错误: $e');
      }
      return;
    }

    final nav = _navigatorKey?.currentState;
    if (nav == null) {
      debugPrint('FrNavigator: navigatorKey 未初始化');
      return;
    }

    nav.push(
      MaterialPageRoute(
        settings: RouteSettings(name: '/fr/${match.host}/${match.path}'),
        builder: (_) => target,
      ),
    );
  }

  static BuildContext _placeholderContext() {
    // 没传 context 时用 navigator 自己的；不常发生（保留防御）
    return _navigatorKey!.currentContext!;
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
