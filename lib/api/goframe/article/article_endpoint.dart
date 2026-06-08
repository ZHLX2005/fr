import '../../api_client.dart';
import '../../api_response.dart';

/// 文章编辑端点 — AI 意图识别 + 内存闭环工具调用。
class ArticleEndpoint {
  final ApiClient _client;

  ArticleEndpoint(this._client);

  Future<ApiResponse<ArticleEditResponse>> edit({
    required String apiKey,
    required String articleToml,
    required String prompt,
    String? model,
    String? baseUrl,
  }) =>
      _client.request<ArticleEditResponse>(
        method: 'POST',
        path: '/api/v1/article/edit',
        body: {
          'apiKey': apiKey,
          'articleToml': articleToml,
          'prompt': prompt,
          if (model != null && model.isNotEmpty) 'model': model,
          if (baseUrl != null && baseUrl.isNotEmpty) 'baseUrl': baseUrl,
        },
        fromJson: (json) => ArticleEditResponse.fromJson(json),
      );
}

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
