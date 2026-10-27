import 'llm_protocol.dart';

/// Anthropic Messages 协议（v1/messages）。
///
/// 直连 api.anthropic.com 或兼容网关。与 OpenAI 的差异点：
/// - 鉴权 `x-api-key` + `anthropic-version` 头（非 Bearer）。
/// - system 提示词独立于 messages。
/// - 图片用 `source: {type: base64, media_type, data}`（非 data URL）。
/// - `max_tokens` 必填。
class AnthropicProtocol extends LlmProtocol {
  static const _version = '2023-06-01';

  const AnthropicProtocol();

  @override
  String get id => 'anthropic';

  @override
  Uri buildUrl(String baseUrl) {
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$trimmed/v1/messages');
  }

  @override
  Map<String, String> buildHeaders(String apiKey) => {
    'x-api-key': apiKey,
    'anthropic-version': _version,
  };

  @override
  Map<String, dynamic> buildBody({
    required String model,
    required String systemPrompt,
    required List<LlmChatMessage> messages,
    int? maxTokens,
  }) {
    if (model.isEmpty) {
      throw const LlmRequestException('模型名不能为空');
    }
    return {
      'model': model,
      // Anthropic 要求 max_tokens 必填；未配置时给个保守默认。
      'max_tokens': maxTokens ?? 1024,
      if (systemPrompt.isNotEmpty) 'system': systemPrompt,
      'messages': messages.map(_encodeMessage).toList(),
    };
  }

  Map<String, dynamic> _encodeMessage(LlmChatMessage m) {
    return {
      'role': m.role == 'system' ? 'user' : m.role,
      'content': [
        for (final img in m.images)
          {
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': img.mediaType,
              'data': img.base64Data,
            },
          },
        {'type': 'text', 'text': m.text},
      ],
    };
  }

  @override
  LlmChatResult parseResponse(Map<String, dynamic> json) {
    final content = json['content'];
    if (content is! List || content.isEmpty) {
      throw const LlmApiException(200, '响应缺少 content');
    }
    // 拼接所有 text 块（thinking 等非 text 块跳过）。
    final text = [
      for (final block in content)
        if (block is Map && block['type'] == 'text' && block['text'] is String)
          block['text'] as String,
    ].join();
    if (text.isEmpty) {
      throw const LlmApiException(200, 'content 中没有 text 块');
    }
    return LlmChatResult(
      text: text,
      model: json['model'] is String ? json['model'] as String : '',
    );
  }
}
