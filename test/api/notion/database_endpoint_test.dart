// NotionDatabaseEndpoint 链路测试。
//
// 验证：
//   1. getDatabase — 拿 me 数据库 schema，属性里必须包含 "名称" (title)
//      和 "创建时间" (created_time)
//   2. queryLatestPage — 按 created_time desc 拿 1 个最新 page，
//      parent 必须是当前 database
//   3. listDatabases — 当前 token 至少能搜到 1 个 database

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/notion/database_endpoint.dart';

import 'notion_test_helpers.dart';

void main() {
  group('NotionDatabaseEndpoint', () {
    late NotionDatabaseEndpoint endpoint;

    setUpAll(() {
      print('--- ${summarizeCreds()} ---');
      endpoint = NotionDatabaseEndpoint(token: requireTestToken());
    });

    test('getDatabase 返回 me 数据库 schema（含名称 + 创建时间 属性）', () async {
      final result = await endpoint.getDatabase(testDatabaseId);

      expect(result['id'], testDatabaseId);
      expect(result['object'], 'database');

      final props = result['properties'] as Map<String, dynamic>;
      expect(props.containsKey('名称'), isTrue,
          reason: 'me 数据库必须有中文 title 属性 "名称"');
      expect(props['名称']['type'], 'title');
      expect(props.containsKey('创建时间'), isTrue);
      expect(props['创建时间']['type'], 'created_time');
    });

    test('queryLatestPage 返回最新 page，parent.database_id 正确', () async {
      final page = await endpoint.queryLatestPage(testDatabaseId);

      expect(page, isNotNull, reason: '数据库里应该至少有一个 page');
      expect(page!['parent']['database_id'], testDatabaseId);
      expect(page['object'], 'page');
      // page id 必须是 UUID
      expect((page['id'] as String).length, 36);
    });

    test('listDatabases 至少能搜到 me 数据库本身', () async {
      final dbs = await endpoint.listDatabases();

      expect(dbs.length, greaterThanOrEqualTo(1));
      final ids = dbs.map((d) => d['id'] as String).toList();
      expect(ids.contains(testDatabaseId), isTrue,
          reason: 'me 数据库必须在搜索结果里');
    });
  });
}