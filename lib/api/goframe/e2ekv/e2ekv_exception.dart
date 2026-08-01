/// e2ekv 异常 — 服务端响应是 `{code, message}` 的裸 JSON，外加 HTTP 状态码。
class E2EKVException implements Exception {
  final int statusCode;
  final String code; // 如 E2EKV_CONFLICT
  final String message;

  E2EKVException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => 'E2EKVException($statusCode $code): $message';
}