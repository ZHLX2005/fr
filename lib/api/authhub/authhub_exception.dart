/// 认证中心调用异常。
///
/// 与 `ApiException`（goframe 业务后端的 `{code,message,data}` 信封）**分开**：
/// OAuth 的错误形状是 RFC 6749 规定的 `{"error":"invalid_grant","error_description":…}`，
/// 没有 code 字段；而错误码本身是**语义**（`invalid_grant` 意味着要重新登录，
/// `server_error` 意味着该重试），必须原样保留给调用方判断。
/// 把两者揉成一个整数 code，就丢掉了这个区分能力。
library;

/// 认证中心相关异常。
class AuthHubException implements Exception {
  /// RFC 6749 的 error 值（invalid_request / invalid_grant / unauthorized_client…），
  /// 或本模块自定义的协议错误名（见下方常量）。
  final String error;

  /// 人类可读说明（来自 error_description，或本地生成）。
  final String message;

  /// HTTP 状态码；纯本地错误为 0。
  final int statusCode;

  const AuthHubException({
    required this.error,
    required this.message,
    this.statusCode = 0,
  });

  // ── 本模块自定义的协议/本地错误名（不是 OAuth 标准值）──────────────────

  /// 拉发现文档失败（认证中心没起来 / 地址配错 / 网络不通）
  static const errDiscovery = 'discovery_unavailable';

  /// 响应不是合法 JSON（多半是中间层返回了 HTML 错误页）
  static const errBadResponse = 'invalid_response';

  /// 用户在授权页主动取消
  static const errCancelled = 'user_cancelled';

  /// 授权回调里没带 code（可能带了 error=access_denied）
  static const errNoCode = 'authorization_no_code';

  /// 回调的 state 与发起时不一致 —— 必须中止，这是防 CSRF 的唯一关口
  static const errStateMismatch = 'state_mismatch';

  /// 认证中心返回了本 App 没申请的 scope 之外的东西，或没返回 id_token
  static const errUnexpectedIdToken = 'unexpected_id_token';

  /// 网络层失败（DNS / 连接被拒 / 超时）。
  ///
  /// 与"认证中心明确拒绝"必须分开：前者应当重试或降级，后者应当清 token。
  /// 合并的话，认证中心重启十几秒就会让所有已登录设备掉线。
  static const errNetwork = 'network_unavailable';

  /// 是否属于"票确实不行"（应当清 token 并重新登录）
  bool get isFatalAuthError =>
      error == 'invalid_grant' ||
      error == 'invalid_token' ||
      error == 'unauthorized_client' ||
      error == 'invalid_client';

  @override
  String toString() =>
      'AuthHubException($error${statusCode == 0 ? '' : ', http $statusCode'}): $message';
}
