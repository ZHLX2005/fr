import 'dart:math';
import 'dart:async';
import '../api_client.dart';
import '../api_response.dart';

/// 指数退避重试拦截器。
///
/// 仅在 [shouldRetry] 返回 true 时重试（默认：5xx 服务端错误）。
class RetryInterceptor extends Interceptor {
  final int maxRetries;
  final bool Function(int code) shouldRetry;

  RetryInterceptor({
    this.maxRetries = 3,
    bool Function(int code)? shouldRetry,
  }) : shouldRetry = shouldRetry ?? ((code) => code >= 500);

  @override
  Future<ApiResponse<T>> intercept<T>(ApiChain<T> chain) async {
    var attempt = 0;
    while (true) {
      try {
        final response = await chain.proceed();
        if (!shouldRetry(response.code) || attempt >= maxRetries) {
          return response;
        }
        await Future.delayed(_backoff(attempt));
        attempt++;
      } catch (_) {
        if (attempt >= maxRetries) rethrow;
        await Future.delayed(_backoff(attempt));
        attempt++;
      }
    }
  }

  Duration _backoff(int attempt) =>
      Duration(milliseconds: 100 * pow(2, attempt).toInt());
}
