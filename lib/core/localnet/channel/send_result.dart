/// 发送结果
class SendResult {
  const SendResult({
    required this.success,
    this.statusCode,
    this.error,
    this.latency = Duration.zero,
  });

  final bool success;
  final int? statusCode;
  final String? error;
  final Duration latency;

  factory SendResult.ok({int? statusCode, Duration latency = Duration.zero}) =>
      SendResult(success: true, statusCode: statusCode, latency: latency);

  factory SendResult.fail(String error, {int? statusCode}) =>
      SendResult(success: false, error: error, statusCode: statusCode);
}
