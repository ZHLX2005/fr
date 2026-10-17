// NotionPageEndpoint 链路测试。
//
// 验证：在 me 数据库下按模板创建新 page（标题 = mention.date + 空格），
//       返回的 page 必须包含正确 parent + 标题结构。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/notion/page_endpoint.dart';

import 'notion_test_helpers.dart';

void main() {
  group('NotionPageEndpoint', () {
    late NotionPageEndpoint endpoint;

    setUpAll(() {
      print('--- ${summarizeCreds()} ---');
      endpoint = NotionPageEndpoint(token: requireTestToken());
    });

    test('createPageWithTimestamp 在 me 数据库下创建新 page', () async {
      final page =
          await endpoint.createPageWithTimestamp(databaseId: testDatabaseId);

      // 1. parent 必须指向 me 数据库
      expect(page['object'], 'page');
      expect(page['parent']['database_id'], testDatabaseId);

      // 2. page id 必须是 UUID
      final pageId = page['id'] as String;
      expect(pageId.length, 36);

      // 3. 标题必须是 mention.date + 空格（与现有 me 数据库 page 风格一致）
      final titleRichText =
          page['properties']['名称']['title'] as List<dynamic>;
      expect(titleRichText.length, 2);
      expect(titleRichText[0]['type'], 'mention');
      expect(titleRichText[0]['mention']['type'], 'date');
      expect(
        titleRichText[0]['mention']['date']['start'],
        isNotEmpty,
      );
      expect(titleRichText[1]['type'], 'text');

      // 4. 留个 page id 在控制台，方便手动清理
      print('--- created page id = $pageId ---');
    });

    test('createPageWithTimestamp 不存在的数据库应抛 NotionApiException', () async {
      const fakeDbId = '00000000-0000-0000-0000-000000000000';
      await expectLater(
        endpoint.createPageWithTimestamp(databaseId: fakeDbId),
        throwsA(isA<Exception>()),
      );
    });
  });
}