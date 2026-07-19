import 'package:flutter/material.dart';

import 'fr_router.dart';

/// fr:// 路由栈跟踪器（CLEAR_TOP 语义依赖）
///
/// 注册到 MaterialApp.navigatorObservers（main.dart），维护当前
/// route 栈（栈底 → 栈顶）。FrNavigator.handle 据此非破坏性地判断
/// 目标路由是否已在栈中——Navigator 公共 API 无法只读扫描全栈
/// （popUntil 会边查边 pop），故用 Observer 同步跟踪。
class FrRouteStack extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];

  /// 是否存在指定 name 的 route（任意深度）
  bool containsName(String name) =>
      _routes.any((r) => r.settings.name == name);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _routes[i] = newRoute;
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
  }
}

/// 全局单例（main.dart 注册到 MaterialApp.navigatorObservers）
final frRouteStack = FrRouteStack();

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

    // 防重复堆叠（CLEAR_TOP 语义）：目标路由已在栈中（任意深度）→
    // popUntil 把已存在实例提到栈顶，不再 push；不在栈中 → 正常 push。
    //
    // 旧实现只查栈顶：桌面 widget 交替点击不同入口、或目标页之上压了
    // 其他页面时，同一页面会被反复 push，"返回手势因此要折叠多次才能退出"。
    // route.isFirst 是保险：Observer 与栈漂移时最多 pop 到根页，不会清空调。
    final routeName = '/fr/${match.authority}/${match.path}';
    if (frRouteStack.containsName(routeName)) {
      nav.popUntil(
        (route) => route.settings.name == routeName || route.isFirst,
      );
      return;
    }

    nav.push(
      MaterialPageRoute(
        settings: RouteSettings(name: routeName),
        builder: (_) => target,
      ),
    );
  }

  static BuildContext _placeholderContext() {
    return _navigatorKey!.currentContext!;
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
