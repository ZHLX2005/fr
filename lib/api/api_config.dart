/// API 配置：baseUrl、超时、重试策略等。
///
/// 生产环境预置 `http://47.110.80.47:8988`，支持运行时切换。
class ApiConfig {
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;

  const ApiConfig({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 240),
    this.maxRetries = 3,
  });

  /// 预置生产环境。当前为真机调试模式：通过 `adb reverse tcp:8080 tcp:8080`
  /// 将真机 127.0.0.1:8080 重定向到开发机的 :8080 后端。
  /// 切回公网部署时改成 `'http://47.110.80.47:8988'` 之类。
  factory ApiConfig.production() => const ApiConfig(
        baseUrl: 'http://127.0.0.1:8080',
      );

  ApiConfig copyWith({
    String? baseUrl,
    Duration? timeout,
    int? maxRetries,
  }) =>
      ApiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        timeout: timeout ?? this.timeout,
        maxRetries: maxRetries ?? this.maxRetries,
      );
}
