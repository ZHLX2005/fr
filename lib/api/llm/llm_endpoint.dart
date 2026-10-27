import 'package:http/http.dart' as http;

import 'anthropic_protocol.dart';
import 'llm_protocol.dart';
import 'openai_protocol.dart';

/// 直连大模型端点 —— 按协议配置把「文本+图片」发给 LLM 并取回文本。
///
/// 自持 [http.Client]（github/notion 模式）：LLM 服务 baseUrl/鉴权与
/// GoFrame 拦截器链完全不同，不混用 ApiClient。端点本身无状态，
/// 配置（协议/baseUrl/apiKey/model）由调用方传入。
class LlmEndpoint {
  final http.Client _client;

  LlmEndpoint({http.Client? client}) : _client = client ?? http.Client();

  static const Map<String, LlmProtocol> protocols = {
    'openai': OpenAiProtocol(),
    'anthropic': AnthropicProtocol(),
  };

  static LlmProtocol protocolById(String id) =>
      protocols[id] ?? const OpenAiProtocol();

  /// 发送一次多模态对话。[settingsJson] 里缺少 apiKey/model/baseUrl 时抛
  /// [LlmRequestException]。
  Future<LlmChatResult> chat({
    required String protocolId,
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required List<LlmChatMessage> messages,
    int? maxTokens,
  }) async {
    final protocol = protocolById(protocolId);
    if (baseUrl.isEmpty) {
      throw const LlmRequestException('baseURL 不能为空');
    }
    if (apiKey.isEmpty) {
      throw const LlmRequestException('API Key 不能为空');
    }
    return protocol.chat(
      client: _client,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      maxTokens: maxTokens,
    );
  }
}
