import 'package:flutter/material.dart';

import 'fr_router.dart';

/// fr:// 路由导航器（基于 frRouter 的 push 封装）
///
/// 替代原 SchemaNavigator，setNavigatorKey 接收 main.dart 的
/// GlobalKey&lt;NavigatorState&gt;，handle 调 frRouter.resolve + handler.build
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

    final handler = frRouter.findHandler(match.authority);
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

    // 防重复堆叠：仅当栈顶 route name 与当前路由前缀一致时才跳过。
    //
    // 桌面 widget / onNewIntent / 文本链接 任一重复触发都会让同一页面被
    // 多次 push，"返回手势因此要折叠多次才能退出"。复用 popUntil 的"谓词
    // 返回 true 立即停止、不 pop"特性做只读探查当前栈顶名字。
    final routeName = '/fr/${match.authority}/${match.path}';
    String? currentName;
    nav.popUntil((route) {
      currentName = route.settings.name;
      return true; // 立即停止，不会 pop 任何页面
    });
    if (currentName == routeName) return;

    nav.push(
      MaterialPageRoute(
        settings: RouteSettings(name: routeName),
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
