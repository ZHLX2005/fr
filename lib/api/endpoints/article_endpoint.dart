import '../api_client.dart';
import '../api_response.dart';

// ════════════════════════════════════════════════════════════════════
// 请求 / 响应模型
// ════════════════════════════════════════════════════════════════════

/// 文章编辑请求。
class ArticleEditRequest {
  final String apiKey;
  final String articleToml;
  final String prompt;
  final String? model;
  final String? baseUrl;

  const ArticleEditRequest({
    required this.apiKey,
    required this.articleToml,
    required this.prompt,
    this.model,
    this.baseUrl,
  });

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'articleToml': articleToml,
        'prompt': prompt,
        if (model != null && model!.isNotEmpty) 'model': model,
        if (baseUrl != null && baseUrl!.isNotEmpty) 'baseUrl': baseUrl,
      };
}

/// 文章编辑响应。
class ArticleEditResponse {
  final String diff;
  final String conclusion;
  final String modifiedToml;
  final bool hasEdit;

  const ArticleEditResponse({
    required this.diff,
    required this.conclusion,
    required this.modifiedToml,
    required this.hasEdit,
  });

  factory ArticleEditResponse.fromJson(Map<String, dynamic> json) =>
      ArticleEditResponse(
        diff: json['diff'] as String? ?? '',
        conclusion: json['conclusion'] as String? ?? '',
        modifiedToml: json['modified_toml'] as String? ?? '',
        hasEdit: json['has_edit'] as bool? ?? false,
      );
}

// ════════════════════════════════════════════════════════════════════
// 端点
// ════════════════════════════════════════════════════════════════════

/// 文章编辑 API 端点。
///
/// 对接后端 goframe 的 POST /api/v1/article/edit。
///
/// ## 闭环流程
/// 1. 前端传入 TOML 文章全文 + 用户 prompt
/// 2. 后端在内存中运行 AI Agent（Supervisor 意图识别）
/// 3. Agent 调用 apply_article_diff 工具修改 TOML
/// 4. 返回 git diff + 结论 + 修改后的 TOML
///
/// ## 使用示例
/// ```dart
/// final client = ApiClient(config: ..., tokenManager: ...);
/// final article = ArticleEndpoint(client);
///
/// final result = await article.edit(
///   apiKey: 'sk-xxx',
///   articleToml: tomlContent,
///   prompt: '把第一段的"深刻改变"改为"悄然改变"',
/// );
/// if (result.isSuccess) {
///   print('diff: ${result.data!.diff}');
///   print('结论: ${result.data!.conclusion}');
/// }
/// ```
class ArticleEndpoint {
  final ApiClient _client;

  ArticleEndpoint(this._client);

  /// 编辑文章：AI 意图识别 + 内存闭环工具调用。
  ///
  /// [apiKey] — API Key（必填）
  /// [articleToml] — 文章 TOML 全文（必填）
  /// [prompt] — 用户编辑/问答要求（必填）
  /// [model] — 模型名（可选，默认 glm-4.7）
  /// [baseUrl] — API 地址（可选，默认使用 ApiConfig.baseUrl）
  Future<ApiResponse<ArticleEditResponse>> edit({
    required String apiKey,
    required String articleToml,
    required String prompt,
    String? model,
    String? baseUrl,
  }) {
    return _client.request<ArticleEditResponse>(
      method: 'POST',
      path: '/api/v1/article/edit',
      body: ArticleEditRequest(
        apiKey: apiKey,
        articleToml: articleToml,
        prompt: prompt,
        model: model,
        baseUrl: baseUrl,
      ).toJson(),
      fromJson: (json) => ArticleEditResponse.fromJson(json),
    );
  }
}
