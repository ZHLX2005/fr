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
///
/// Router 行为：
/// - 注册：每个 FrRoute.authority 作为前缀注册到 _routes（_routes key = authority）。
/// - 查询：findHandler 遍历所有已注册 route，找到第一个
///   `registeredAuthority == incomingAuthority || incomingAuthority.startsWith(registeredAuthority + '/')`
///   的 route。'lab/demo' 路由 'lab/demo/clock'；'lab' 不会路由 'lab/demo'（避免
///   误匹配到 LabIndexHandler）。最长 prefix 优先，确保 'lab/demo' 在 'lab' 之前被命中。
class FrRouter {
  final Map<String, FrRoute> _routes = {};

  /// 注册单条路由
  void register(FrRoute route) {
    _routes[route.authority] = route;
  }

  /// 批量注册
  void registerAll(Iterable<FrRoute> routes) {
    for (final r in routes) {
      register(r);
    }
  }

  /// 按 authority 找 handler（prefix 匹配；最长优先）。
  ///
  /// 算法：对每个已注册 authority，判定
  /// `incoming == registered || incoming.startsWith(registered + '/')`，
  /// 取匹配中最长的 registered 返回。
  FrRouteHandler? findHandler(String authority) {
    FrRouteHandler? best;
    var bestLen = -1;
    for (final entry in _routes.entries) {
      final reg = entry.key;
      if (authority == reg || authority.startsWith('$reg/')) {
        if (reg.length > bestLen) {
          best = entry.value.handler;
          bestLen = reg.length;
        }
      }
    }
    return best;
  }

  /// 列出已注册的所有 authority（调试/测试用）
  Iterable<String> get registeredAuthorities => _routes.keys;

  /// 解析 URL 并 dispatch 到 handler
  ///
  /// - 解析失败（scheme 错误）→ debugPrint + 静默返回
  /// - 找不到 authority → debugPrint + 静默返回（callSite 决定是否 SnackBar）
  /// - handler 抛异常 → debugPrint + 抛（callSite 决定 SnackBar）
  ///
  /// Navigator.push 由 callSite 通过 [dispatch] 调，本方法不直接做 push。
  Future<FrRouteMatch?> resolve(String url) async {
    final uri = FrUri.tryParse(url);
    if (uri == null) {
      debugPrint('FrRouter: 无法解析 url: $url');
      return null;
    }
    final handler = findHandler(uri.authority);
    if (handler == null) {
      debugPrint('FrRouter: 未知 authority: ${uri.authority}');
      return null;
    }
    return FrRouteMatch(uri);
  }
}

/// 全局单例
final frRouter = FrRouter();
