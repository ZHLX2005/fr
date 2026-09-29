import 'dart:convert';

/// pi（nx-as）接口异常。
///
/// 网关与 pi-web 的错误响应对齐 `{ ok:false, error, code }` 或 `{ error }`，
/// 这里统一解析出 [code] 与 [message]，供上层判断可重试 / 需登录 / 参数问题。
class PiApiException implements Exception {
  /// HTTP 状态码；0 表示网络层失败（未拿到响应）。
  final int statusCode;

  /// 业务错误码（如 `UNAUTHORIZED`、`prompt_rejected`），无则为 null。
  final String? code;

  final String message;
  final String? rawBody;

  const PiApiException({
    required this.statusCode,
    required this.message,
    this.code,
    this.rawBody,
  });

  /// 凭据问题：token 缺失/无效/被吊销。
  bool get isUnauthorized => statusCode == 401 || code == 'UNAUTHORIZED';

  /// 被限流（网关节流：失败次数过多）。
  bool get isThrottled => statusCode == 429;

  /// 会话不存在（典型：拿过期 sessionId 发消息）。
  bool get isSessionMissing => statusCode == 404;

  /// 网络层失败（不是服务端返回的错误）。
  bool get isNetworkError => statusCode == 0;

  /// 从 HTTP 响应构造。响应体若不是预期 JSON，退化为纯文本 message。
  factory PiApiException.fromResponse(int statusCode, String body) {
    String? code;
    String message = body;
    try {
      final decoded = json.decode(body);
      if (decoded is Map<String, dynamic>) {
        message = (decoded['error'] ?? decoded['message'] ?? body).toString();
        final c = decoded['code'];
        if (c is String && c.isNotEmpty) code = c;
      }
    } catch (_) {
      // 非 JSON（如 nginx 的 HTML 错误页）——保留原文，方便排查
    }
    return PiApiException(
      statusCode: statusCode,
      message: message,
      code: code,
      rawBody: body,
    );
  }

  @override
  String toString() =>
      'PiApiException($statusCode${code != null ? ' $code' : ''}): $message';
}
