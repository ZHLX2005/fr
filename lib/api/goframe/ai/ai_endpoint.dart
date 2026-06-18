import '../../api_client.dart';
import '../../api_response.dart';

/// AI 端点 — 通用对话、文章编辑等。
///
/// 覆盖后端 `internal/service/ai` 暴露的所有 AI 能力。
class AiEndpoint {
  final ApiClient _client;

  AiEndpoint(this._client);

  /// 通用对话（闲聊 / 问答）。
  ///
  /// 对应后端 `POST /api/v1/ai/chat`，agent 走 `base_chat` runner。
  /// 与 [ArticleEndpoint.edit] 的区别：chat 不修改任何文章结构，
  /// 仅返回 AI 的回复文本（`content`），适合多轮闲聊场景。
  ///
  /// 参数 [apiKey] — LLM 供应商 API Key（必填）。
  /// 参数 [prompt] — 用户问题（必填）。
  /// 参数 [model] — 模型名（可选）。空时后端用默认模型。
  /// 参数 [baseUrl] — LLM API 地址（可选）。空时后端用默认地址。
  ///   ⚠️ **字段名约定**：后端 swagger 字段名是 `baseURL`（全大写 URL），
  ///   不是 `baseUrl`（驼峰）。前端必须用 JSON key `baseURL`，否则后端
  ///   unmarshal 时会**静默丢弃**该字段。
  /// 参数 [type] — 模型类型（可选，默认 "claude"）。
  Future<ApiResponse<ChatResponse>> chat({
    required String apiKey,
    required String prompt,
    String? model,
    String? baseUrl,
    String? type,
  }) =>
      _client.request<ChatResponse>(
        method: 'POST',
        path: '/api/v1/ai/chat',
        body: {
          'apiKey': apiKey,
          'prompt': prompt,
          if (model != null && model.isNotEmpty) 'model': model,
          if (baseUrl != null && baseUrl.isNotEmpty) 'baseURL': baseUrl,
          if (type != null && type.isNotEmpty) 'type': type,
        },
        fromJson: (json) => ChatResponse.fromJson(json),
      );
}

/// 通用对话响应。
class ChatResponse {
  /// AI 的回复内容。
  final String content;

  const ChatResponse({required this.content});

  factory ChatResponse.fromJson(Map<String, dynamic> json) =>
      ChatResponse(content: json['content'] as String? ?? '');
}
