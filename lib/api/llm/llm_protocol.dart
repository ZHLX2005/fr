import 'dart:convert';

import 'package:http/http.dart' as http;

/// LLM 请求构造失败（协议参数非法等）。
class LlmRequestException implements Exception {
  final String message;
  const LlmRequestException(this.message);

  @override
  String toString() => 'LlmRequestException: $message';
}

/// LLM 服务端错误（4xx/5xx）。
class LlmApiException implements Exception {
  final int statusCode;
  final String message;
  const LlmApiException(this.statusCode, this.message);

  @override
  String toString() => 'LlmApiException($statusCode): $message';
}

/// 单张图片输入（base64 传值，双协议共用的中间表示）。
class LlmImage {
  /// 纯 base64 数据（不带 `data:` 前缀）。
  final String base64Data;

  /// MIME 类型，如 `image/jpeg`。
  final String mediaType;

  const LlmImage({required this.base64Data, this.mediaType = 'image/jpeg'});

  /// `data:image/jpeg;base64,...` 完整 data URL（OpenAI 协议用）。
  String get dataUrl => 'data:$mediaType;base64,$base64Data';
}

/// 对话消息：文本 + 可选图片（vision）。
class LlmChatMessage {
  /// `user` / `system`。
  final String role;
  final String text;
  final List<LlmImage> images;

  const LlmChatMessage({
    this.role = 'user',
    required this.text,
    this.images = const [],
  });
}

/// 一次对话的统一结果（双协议归一）。
class LlmChatResult {
  final String text;

  /// 响应里声明的实际模型名（各家字段不同，可能为空）。
  final String model;

  const LlmChatResult({required this.text, this.model = ''});
}

/// 协议抽象 —— OpenAI 兼容与 Anthropic 各自实现请求构造与响应解析。
///
/// 结构参考 `.claude/repo/ai_clients_dart`（openai_dart / anthropic_sdk_dart）：
/// - OpenAI：`Authorization: Bearer` + `messages[].content` 多段数组，
///   图片用 `image_url.url = data:<mime>;base64,<data>`。
/// - Anthropic：`x-api-key` + `anthropic-version` 头，`system` 独立于 messages，
///   图片用 `source: {type: base64, media_type, data}`。
abstract class LlmProtocol {
  const LlmProtocol();
  /// 协议标识（持久化用）：`openai` / `anthropic`。
  String get id;

  /// 构造完整请求 URL。
  Uri buildUrl(String baseUrl);

  /// 构造请求头。
  Map<String, String> buildHeaders(String apiKey);

  /// 构造请求体。抛 [LlmRequestException] 表示参数非法。
  Map<String, dynamic> buildBody({
    required String model,
    required String systemPrompt,
    required List<LlmChatMessage> messages,
    int? maxTokens,
  });

  /// 解析响应 JSON 中的回复文本。抛 [LlmApiException] 表示协议级错误。
  LlmChatResult parseResponse(Map<String, dynamic> json);

  /// 发送一次对话并归一结果。全部协议共用这条链路。
  Future<LlmChatResult> chat({
    required http.Client client,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<LlmChatMessage> messages,
    int? maxTokens,
  }) async {
    final uri = buildUrl(baseUrl);
    final body = buildBody(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      maxTokens: maxTokens,
    );
    final resp = await client.post(
      uri,
      headers: {...buildHeaders(apiKey), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw LlmApiException(resp.statusCode, _extractErrorMessage(resp.body));
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return parseResponse(json);
  }

  /// 尽力从错误响应体里抠出可读信息（各家错误形状不同）。
  static String _extractErrorMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        // OpenAI: {error: {message}}；Anthropic: {error: {message}}
        final error = json['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (error is String) return error;
        if (json['message'] is String) return json['message'] as String;
      }
    } catch (_) {}
    if (body.length > 300) body = body.substring(0, 300);
    return body;
  }
}
