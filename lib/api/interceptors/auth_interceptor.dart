import '../token/token_manager.dart';
import '../api_client.dart';
import '../api_response.dart';

/// Bearer Token 拦截器。
///
/// 当前后端 Auth 中间件为可选，无 token 时自动跳过。
/// **已接入但待用** — 未来启用 auth 后只需在 TokenManager 中设置 token 即可。
class AuthInterceptor extends Interceptor {
  final TokenManager tokenManager;

  AuthInterceptor({required this.tokenManager});

  @override
  Future<ApiResponse<T>> intercept<T>(ApiChain<T> chain) async {
    // 有 token 则注入，无 token 则跳过
    final token = await tokenManager.accessToken;
    if (token != null && token.isNotEmpty) {
      chain.headers['Authorization'] = 'Bearer $token';
    }

    var response = await chain.proceed();

    // 401 时尝试 refresh 后重试一次
    if (response.code == 401) {
      final refreshed = await tokenManager.tryRefresh();
      if (refreshed) {
        final newToken = await tokenManager.accessToken;
        if (newToken != null && newToken.isNotEmpty) {
          chain.headers['Authorization'] = 'Bearer $newToken';
          response = await chain.proceed();
        }
      }
    }
    return response;
  }
}
