import 'package:flutter/widgets.dart';

import 'fr_uri.dart';

/// 路由匹配结果 — handler.build() 拿到的入参
///
/// 包含 authority/path/query 三段，handler 通过工具方法取值。
class FrRouteMatch {
  final FrUri uri;

  const FrRouteMatch(this.uri);

  /// 整段 authority（如 'lab'、'lab/demo/clock'、'notion/image-host'）。
  /// Router 用整段做 prefix 匹配，handler 用整段做最终验证。
  String get authority => uri.authority;

  /// authority 内第一个 '/' 之后的部分（保留给 handler 拆分）。
  String get path => uri.path;

  Map<String, String> get query => uri.query;

  /// 取 query 字符串值，不存在返回 null
  String? queryString(String key) => query[key];

  /// 取 query 布尔值；接受 'true'/'1' 为 true，其他为 defaultValue
  bool queryBool(String key, {bool defaultValue = false}) {
    final v = query[key];
    if (v == null) return defaultValue;
    return v == 'true' || v == '1';
  }

  /// 拆 path 段（按 '/'）；越界抛 RangeError
  String pathSegment(int index) {
    if (path.isEmpty) {
      throw RangeError.index(index, path, 'path is empty');
    }
    final segments = path.split('/');
    if (index < 0 || index >= segments.length) {
      throw RangeError.index(index, segments, 'path segments');
    }
    return segments[index];
  }
}

/// 路由处理器抽象基类
///
/// 每个 authority 对应一个 handler 子类；handler 拿到 context 和 match，
/// 返回要 push 的 Widget。
abstract class FrRouteHandler {
  const FrRouteHandler();

  /// 构建目标 Widget
  ///
  /// context 来自调用方（可能为 null，见各 frRouter.handle 重载）；
  /// match 包含 URI 全部信息。
  Widget build(BuildContext context, FrRouteMatch match);
}
