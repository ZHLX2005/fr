import '../../../../api/api_response.dart';
import '../../../../api/goframe/article/article_endpoint.dart';
import '../../../../core/note/note_root_scope.dart';
import 'ai_settings_store.dart';

/// 调用后端 article/edit 的函数签名（= ArticleEndpoint.edit 的 tear-off 类型）。
typedef ArticleEditCall =
    Future<ApiResponse<ArticleEditResponse>> Function({
  required String apiKey,
  required String articleToml,
  required String prompt,
  String? model,
  String? baseUrl,
});

/// article/edit 的结果（已做 Block 转换）。
class ArticleEditResult {
  final bool hasEdit;
  final String conclusion;
  final String diff;
  final Block? modifiedBlock;

  const ArticleEditResult({
    required this.hasEdit,
    required this.conclusion,
    required this.diff,
    this.modifiedBlock,
  });
}

class ArticleEditException implements Exception {
  final String message;
  ArticleEditException(this.message);
  @override
  String toString() => 'ArticleEditException: $message';
}

/// 封装 Block → TOML → endpoint → TOML → Block 的完整链路。
class ArticleEditService {
  final ArticleEditCall _editCall;
  final NoteFactory _noteFactory;

  ArticleEditService({required ArticleEditCall editCall, required NoteFactory noteFactory})
      : _editCall = editCall,
        _noteFactory = noteFactory;

  factory ArticleEditService.forEndpoint(ArticleEndpoint endpoint, NoteFactory noteFactory) {
    return ArticleEditService(editCall: endpoint.edit, noteFactory: noteFactory);
  }

  Future<ArticleEditResult> edit({
    required Block rootNote,
    required String prompt,
    required AiSettings settings,
  }) async {
    final toml = _noteFactory.toTomlString(rootNote);
    final resp = await _editCall(
      apiKey: settings.apiKey,
      articleToml: toml,
      prompt: prompt,
      model: settings.model.isEmpty ? null : settings.model,
      baseUrl: settings.baseUrl.isEmpty ? null : settings.baseUrl,
    );

    if (!resp.isSuccess || resp.data == null) {
      throw ArticleEditException(resp.message.isEmpty ? '请求失败' : resp.message);
    }
    final d = resp.data!;

    Block? modified;
    if (d.hasEdit) {
      modified = _noteFactory.fromTomlString(d.modifiedToml);
      if (modified == null) {
        throw ArticleEditException('修改后的 TOML 解析失败');
      }
    }

    return ArticleEditResult(
      hasEdit: d.hasEdit,
      conclusion: d.conclusion,
      diff: d.diff,
      modifiedBlock: modified,
    );
  }
}
