/// API 配置：baseUrl、超时、重试策略等。
///
/// 生产环境预置 `http://47.110.80.47:8988`，支持运行时切换。
class ApiConfig {
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;

  const ApiConfig({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 3,
  });

  /// 预置生产环境（与现有 [ApiService.baseUrl] 一致）。
  factory ApiConfig.production() => const ApiConfig(
        baseUrl: 'http://47.110.80.47:8988',
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
