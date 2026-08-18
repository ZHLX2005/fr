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

  /// 灵活对话（flex）—— 支持 DB 模板（[template]）、自定义提示词（[customPrompt]）
  /// 与图片输入（[images]）。小票 OCR 等场景通过 `template: 'receipt_ocr'`
  /// 引用 DB 里的唯一可信源提示词。
  ///
  /// 对应后端 `POST /api/v1/ai/chat/flex`。
  /// ⚠️ [baseUrl] → JSON key `baseURL`（全大写 URL，同 [chat]）。
  /// ⚠️ apiKey 在请求体里自带鉴权，后端 flex 中间件不强制 JWT。
  /// [images] 元素形如 `{'base64': 'data:image/jpeg;base64,...', 'detail': 'high'}`。
  Future<ApiResponse<FlexChatResponse>> flexChat({
    required String apiKey,
    required String prompt,
    String? model,
    String? baseUrl,
    String? type,
    String template = '',
    String customPrompt = '',
    List<Map<String, dynamic>>? images,
    int? maxTokens,
  }) =>
      _client.request<FlexChatResponse>(
        method: 'POST',
        path: '/api/v1/ai/chat/flex',
        body: {
          'apiKey': apiKey,
          'prompt': prompt,
          if (model != null && model.isNotEmpty) 'model': model,
          if (baseUrl != null && baseUrl.isNotEmpty) 'baseURL': baseUrl,
          if (type != null && type.isNotEmpty) 'type': type,
          'template': template,
          'customPrompt': customPrompt,
          if (images != null) 'images': images,
          if (maxTokens != null) 'maxTokens': maxTokens,
        },
        fromJson: (json) => FlexChatResponse.fromJson(json),
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

/// flex 对话响应。
class FlexChatResponse {
  /// AI 的回复内容（小票 OCR 场景下是 JSON 串，可能裹在 ```json 代码块里）。
  final String content;
  /// 实际命中的模板名（builtin 或 DB name）。
  final String template;
  /// 实际使用的模型名。
  final String model;
  /// 携带的图片数。
  final int imageCount;

  const FlexChatResponse({
    required this.content,
    required this.template,
    required this.model,
    required this.imageCount,
  });

  factory FlexChatResponse.fromJson(Map<String, dynamic> json) =>
      FlexChatResponse(
        content: json['content'] as String? ?? '',
        template: json['template'] as String? ?? '',
        model: json['model'] as String? ?? '',
        imageCount: json['imageCount'] as int? ?? 0,
      );
}
