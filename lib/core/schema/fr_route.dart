import 'fr_route_handler.dart';

/// 路由条目：host 命名空间 + handler 引用
///
/// 用法:
/// ```dart
/// FrRoute('lab/demo', handler: const LabDemoHandler())
/// ```
class FrRoute {
  /// host 段（fr:// 之后第一个 '/' 之前的部分）
  final String host;

  /// 该 host 下的处理器
  final FrRouteHandler handler;

  const FrRoute(this.host, {required this.handler});
}