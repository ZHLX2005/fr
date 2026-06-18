import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/api_response.dart';
import 'package:xiaodouzi_fr/api/goframe/article/article_endpoint.dart';
import 'package:xiaodouzi_fr/core/note/note_root_scope.dart';
import 'package:xiaodouzi_fr/lab/demos/block_editor_demo/ai/ai_settings_store.dart';
import 'package:xiaodouzi_fr/lab/demos/block_editor_demo/ai/article_edit_service.dart';

ArticleEditResponse _editResponse({required bool hasEdit}) {
  if (!hasEdit) {
    return const ArticleEditResponse(
      diff: '',
      conclusion: '这篇文章讲 AI。',
      modifiedToml: '',
      hasEdit: false,
    );
  }
  // hasEdit=true：modifiedToml 必须是合法 TOML，能被 NoteFactory.fromTomlString 解析
  const toml = 'id = "root"\ntype = "page"\ncontent = { spans = [{ text = "" }] }\nchildren = []\ndata = {}\nproperties = {}\ncreated_at = 1\nupdated_at = 2\n';
  return const ArticleEditResponse(
    diff: '@@ -1,1 +1,1 @@\n-old\n+new',
    conclusion: '修改完成',
    modifiedToml: toml,
    hasEdit: true,
  );
}

void main() {
  late NoteFactory noteFactory;

  setUp(() {
    noteFactory = NoteFactory.create();
  });

  test('edit returns hasEdit=true with parsed modifiedBlock', () async {
    final service = ArticleEditService(
      editCall: ({required apiKey, required articleToml, required prompt, model, baseUrl}) async =>
          ApiResponse(code: 0, message: '', data: _editResponse(hasEdit: true)),
      noteFactory: noteFactory,
    );
    final root = Block(id: 'root', type: const PageType());

    final result = await service.edit(
      rootNote: root,
      prompt: '改一下',
      settings: const AiSettings(apiKey: 'sk-x'),
    );

    expect(result.hasEdit, isTrue);
    expect(result.diff, contains('-old'));
    expect(result.modifiedBlock, isNotNull);
  });

  test('edit returns hasEdit=false with conclusion, no modifiedBlock', () async {
    final service = ArticleEditService(
      editCall: ({required apiKey, required articleToml, required prompt, model, baseUrl}) async =>
          ApiResponse(code: 0, message: '', data: _editResponse(hasEdit: false)),
      noteFactory: noteFactory,
    );

    final result = await service.edit(
      rootNote: Block(id: 'r', type: const PageType()),
      prompt: '主题是什么',
      settings: const AiSettings(apiKey: 'sk-x'),
    );

    expect(result.hasEdit, isFalse);
    expect(result.conclusion, '这篇文章讲 AI。');
    expect(result.modifiedBlock, isNull);
  });

  test('edit throws on non-success response', () async {
    final service = ArticleEditService(
      editCall: ({required apiKey, required articleToml, required prompt, model, baseUrl}) async =>
          ApiResponse<ArticleEditResponse>(code: 500, message: 'server boom', data: null),
      noteFactory: noteFactory,
    );

    expect(
      () => service.edit(
        rootNote: Block(id: 'r', type: const PageType()),
        prompt: 'x',
        settings: const AiSettings(apiKey: 'sk-x'),
      ),
      throwsA(isA<ArticleEditException>()),
    );
  });
}
