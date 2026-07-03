import 'fr_route_handler.dart';

/// 路由条目：authority 命名空间 + handler 引用
///
/// 用法:
/// ```dart
/// FrRoute('lab/demo', handler: const LabDemoHandler())
/// ```
class FrRoute {
  /// authority 段（fr:// 之后、? 之前的整段；可以是 'lab'、'lab/demo'、
  /// 'notion/image-host'）。Router 用 prefix 匹配：'lab/demo' 路由
  /// 'fr://lab/demo/clock'，'lab' 路由 'fr://lab'。
  final String authority;

  /// 该 authority 下的处理器
  final FrRouteHandler handler;

  const FrRoute(this.authority, {required this.handler});
}
