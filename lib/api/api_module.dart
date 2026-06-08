/// API 模块 — 后端 goframe HTTP 客户端封装。
///
/// 架构：ApiClient（拦截器链）→ endpoints（业务端点）
///
/// ## 拦截器链（按序执行）
/// 1. [AuthInterceptor] — 有 token 时注入；当前后端 auth 可选，无 token 跳过
/// 2. [LoggingInterceptor] — 请求/响应日志
/// 3. [RetryInterceptor] — 5xx 指数退避重试
library;

export 'api_config.dart';
export 'api_client.dart';
export 'api_response.dart';
export 'token/token_manager.dart';
export 'token/token_storage.dart';
export 'interceptors/auth_interceptor.dart';
export 'interceptors/logging_interceptor.dart';
export 'interceptors/retry_interceptor.dart';
export 'endpoints/article_endpoint.dart';
