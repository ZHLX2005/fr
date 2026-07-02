/// Notion API 异常 — 解析 4xx/5xx 响应里的 code/message。
///
/// 与 `github/github_exception.dart` 同形，便于上层统一捕获。
class NotionApiException implements Exception {
  final int statusCode;
  final String code; // 例如 "validation_error"、"unauthorized"
  final String message;

  const NotionApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() =>
      'NotionApiException($statusCode $code): $message';
}