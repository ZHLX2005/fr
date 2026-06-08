/// 统一 API 响应包装，对齐后端 goframe 的 `{ code, message, data }` 结构。
class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;

  const ApiResponse({required this.code, required this.message, this.data});

  bool get isSuccess => code == 0;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T? Function(dynamic)? fromJsonT,
  ) =>
      ApiResponse(
        code: json['code'] as int? ?? -1,
        message: json['message'] as String? ?? '',
        data: json['data'] != null && fromJsonT != null
            ? fromJsonT(json['data'])
            : null,
      );
}

/// API 请求异常。
class ApiException implements Exception {
  final int code;
  final String message;
  final String? rawBody;

  const ApiException({
    required this.code,
    required this.message,
    this.rawBody,
  });

  @override
  String toString() => 'ApiException($code): $message';
}
