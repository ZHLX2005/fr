import 'package:flutter/widgets.dart';

import 'fr_route.dart';
import 'fr_route_handler.dart';
import 'fr_uri.dart';

/// fr:// 路由注册中心（单例）
///
/// 使用:
/// ```dart
/// frRouter.register(FrRoute('lab', handler: const LabIndexHandler()));
/// await frRouter.handle(context, 'fr://lab/demo/clock');
/// ```
class FrRouter {
  final Map<String, FrRoute> _routes = {};

  /// 注册单条路由
  void register(FrRoute route) {
    _routes[route.host] = route;
  }

  /// 批量注册
  void registerAll(Iterable<FrRoute> routes) {
    for (final r in routes) {
      register(r);
    }
  }

  /// 查 host 对应的 handler，找不到返回 null
  FrRouteHandler? findHandler(String host) => _routes[host]?.handler;

  /// 列出已注册的所有 host（调试/测试用）
  Iterable<String> get registeredHosts => _routes.keys;

  /// 解析 URL 并 dispatch 到 handler
  ///
  /// - 解析失败（scheme 错误）→ debugPrint + 静默返回
  /// - 找不到 host → debugPrint + 静默返回（callSite 决定是否 SnackBar）
  /// - handler 抛异常 → debugPrint + 抛（callSite 决定 SnackBar）
  ///
  /// Navigator.push 由 callSite 通过 [dispatch] 调，本方法不直接做 push。
  Future<FrRouteMatch?> resolve(String url) async {
    final uri = FrUri.tryParse(url);
    if (uri == null) {
      debugPrint('FrRouter: 无法解析 url: $url');
      return null;
    }
    final handler = findHandler(uri.host);
    if (handler == null) {
      debugPrint('FrRouter: 未知 host: ${uri.host}');
      return null;
    }
    return FrRouteMatch(uri);
  }
}

/// 全局单例
final frRouter = FrRouter();
