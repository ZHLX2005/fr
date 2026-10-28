import 'llm_protocol.dart';

/// OpenAI 兼容协议（chat/completions）。
///
/// 兼容所有 `*/v1/chat/completions` 形状的服务：OpenAI 官方、各类中转、
/// DeepSeek / Moonshot / GLM 等。图片按 vision 约定走 data URL。
class OpenAiProtocol extends LlmProtocol {
  /// 请求路径（默认官方形状；中转服务如路径不同可覆盖）。
  final String path;

  const OpenAiProtocol({this.path = '/v1/chat/completions'});

  @override
  String get id => 'openai';

  @override
  Uri buildUrl(String baseUrl) {
    final trimmed = baseUrl.replaceAll(RegExp(r'/+$'), '');
    // path 形如 /v1/chat/completions；baseUrl 已带 /v1 时去重，避免 /v1/v1/。
    final url = trimmed.endsWith('/v1')
        ? '$trimmed${path.substring('/v1'.length)}'
        : '$trimmed$path';
    return Uri.parse(url);
  }

  @override
  Map<String, String> buildHeaders(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
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
      'messages': [
        if (systemPrompt.isNotEmpty)
          {'role': 'system', 'content': systemPrompt},
        ...messages.map(_encodeMessage),
      ],
      // 空感知元素语法（'max_tokens': ?maxTokens）CI 的 analyzer 6.x 解析不了（见 pubspec hive_generator 注释）
      if (maxTokens != null) 'max_tokens': maxTokens,
    };
  }

  /// 文本 + 图片混排成 content 数组（纯文本时退化为单字符串，兼容性最好）。
  Map<String, dynamic> _encodeMessage(LlmChatMessage m) {
    if (m.images.isEmpty) {
      return {'role': m.role, 'content': m.text};
    }    return {
      'role': m.role,
      'content': [
        {'type': 'text', 'text': m.text},
        for (final img in m.images)
          {
            'type': 'image_url',
            'image_url': {'url': img.dataUrl, 'detail': 'high'},
          },
      ],
    };
  }

  @override
  LlmChatResult parseResponse(Map<String, dynamic> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmApiException(200, '响应缺少 choices');
    }
    final first = choices.first;
    if (first is! Map) {
      throw const LlmApiException(200, 'choices[0] 形状异常');
    }
    final message = first['message'];
    final content = message is Map ? message['content'] : null;
    if (content is! String) {
      throw const LlmApiException(200, 'choices[0].message.content 缺失');
    }
    return LlmChatResult(
      text: content,
      model: json['model'] is String ? json['model'] as String : '',
    );
  }
}
