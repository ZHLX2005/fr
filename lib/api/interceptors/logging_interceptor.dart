import 'dart:developer' as dev;
import '../api_client.dart';
import '../api_response.dart';

/// 请求/响应日志拦截器。
class LoggingInterceptor extends Interceptor {
  final bool logBody;

  LoggingInterceptor({this.logBody = false});

  @override
  Future<ApiResponse<T>> intercept<T>(ApiChain<T> chain) async {
    final start = DateTime.now();
    dev.log('[API] --> ${chain.method} ${chain.path}', name: 'api');

    try {
      final response = await chain.proceed();
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      dev.log('[API] <-- ${chain.method} ${chain.path} → ${response.code} (${elapsed}ms)', name: 'api');
      if (logBody && response.data != null) {
        dev.log('[API] body: ${response.data}', name: 'api');
      }
      return response;
    } catch (e) {
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      dev.log('[API] <-- ${chain.method} ${chain.path} → ERROR (${elapsed}ms): $e', name: 'api');
      rethrow;
    }
  }
}
