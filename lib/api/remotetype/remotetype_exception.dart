// lib/api/remotetype/remotetype_exception.dart

/// 远程输入桥的错误。
///
/// 分类按**用户下一步该做什么**划，不按 HTTP 状态码划：这几种情况的处理动作
/// 完全不同，混成一类就只能显示"连接失败"。
enum RemoteTypeErrorKind {
  /// 服务端没开启统一登录 —— 不是故障，退回手工配对 key 的旧用法即可。
  authDisabled,

  /// 服务端可达但不认识这枚授权码/令牌 —— 需要重新走一次授权。
  unauthorized,

  /// 服务端根本没连上认证中心（issuer 写错、容器出网不通）。
  idpUnavailable,

  /// 这台电脑已被**别人**绑定过。绝不静默改绑，也不假装连上了。
  ownedByOther,

  /// 地址不可达、超时、返回的不是 JSON。
  unreachable,
}

class RemoteTypeException implements Exception {
  const RemoteTypeException(this.kind, this.message, {this.detail});

  final RemoteTypeErrorKind kind;
  final String message;
  final String? detail;

  /// 服务端是否支持统一登录。false 时 UI 要退回手工 key，而不是报错。
  bool get isAuthDisabled => kind == RemoteTypeErrorKind.authDisabled;

  @override
  String toString() => detail == null ? message : '$message（$detail）';
}
