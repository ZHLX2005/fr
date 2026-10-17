// 一次性诊断测试：用真 token 调 Notion /v1/search，确认 listDatabases 失效根因。
//
// 验证三件事：
//   A. filter.value="database"（当前代码）— 是否返回 0 条 / 报错 / 还是能拿
//   B. filter.value="data_source" — 新版 API 的正确值，预期拿到真实 db 列表
//   C. 不带 filter — 拿全量，看返回什么 object 类型（page vs data_source vs database）
//
// 跑法：
//   flutter test test/api/notion/diagnose_search_test.dart \
//     --dart-define=NOTION_TOKEN=<token> --reporter expanded

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/api/notion/database_endpoint.dart';
import 'package:xiaodouzi_fr/api/notion/notion_exception.dart';

void main() {
  const token = String.fromEnvironment('NOTION_TOKEN', defaultValue: '');
  const version = '2022-06-28';

  setUpAll(() {
    if (token.isEmpty) {
      throw StateError(
        '用法: flutter test test/api/notion/diagnose_search_test.dart '
        '--dart-define=NOTION_TOKEN=<你的token>',
      );
    }
  });

  Future<Map<String, dynamic>> postSearch(
    Map<String, dynamic> body,
  ) async {
    final client = http.Client();
    try {
      final resp = await client.post(
        Uri.parse('https://api.notion.com/v1/search'),
        headers: {
          'Authorization': 'Bearer $token',
          'Notion-Version': version,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      if (resp.statusCode >= 400) {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        throw NotionApiException(
          statusCode: resp.statusCode,
          code: decoded['code'] as String? ?? 'unknown',
          message: decoded['message'] as String? ?? 'HTTP ${resp.statusCode}',
        );
      }
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Map<String, int> objectDistribution(List<dynamic> results) {
    final dist = <String, int>{};
    for (final r in results) {
      final obj = (r as Map<String, dynamic>)['object'] as String? ?? '?';
      dist[obj] = (dist[obj] ?? 0) + 1;
    }
    return dist;
  }

  test('A. 当前代码: filter.value=database', () async {
    print('\n═══ A. filter.value=database (当前代码用的) ═══');
    final body = await postSearch({
      'filter': {'value': 'database', 'property': 'object'},
      'page_size': 50,
    });
    final results = (body['results'] as List<dynamic>?) ?? [];
    print('results.length = ${results.length}');
    print('object 分布: ${objectDistribution(results)}');
    if (results.isNotEmpty) {
      final first = results.first as Map<String, dynamic>;
      print('第一条 object=${first['object']} id=${first['id']}');
      print('第一条 title 字段 (前 200 char): '
          '${jsonEncode(first['title']).toString().substring(0, 200)}');
    }
  }, tags: ['diagnose']);

  test('B. 新版: filter.value=data_source', () async {
    print('\n═══ B. filter.value=data_source (新版) ═══');
    final body = await postSearch({
      'filter': {'value': 'data_source', 'property': 'object'},
      'page_size': 50,
    });
    final results = (body['results'] as List<dynamic>?) ?? [];
    print('results.length = ${results.length}');
    print('object 分布: ${objectDistribution(results)}');
    if (results.isNotEmpty) {
      final first = results.first as Map<String, dynamic>;
      print('第一条 object=${first['object']} id=${first['id']}');
      print('第一条 title 字段 (前 200 char): '
          '${jsonEncode(first['title']).toString().substring(0, 200)}');
    }
  }, tags: ['diagnose']);

  test('C. 无 filter: 看返回什么类型', () async {
    print('\n═══ C. 无 filter (搜全部) ═══');
    final body = await postSearch({'page_size': 50});
    final results = (body['results'] as List<dynamic>?) ?? [];
    print('results.length = ${results.length}');
    print('object 分布: ${objectDistribution(results)}');
  }, tags: ['diagnose']);

  test('D. 走真实 listDatabases(): 抓异常 + 解析失败', () async {
    print('\n═══ D. NotionDatabaseEndpoint.listDatabases() 实跑 ═══');
    final endpoint = NotionDatabaseEndpoint(token: token);
    try {
      final dbs = await endpoint.listDatabases();
      print('返回 dbs.length = ${dbs.length}');
      if (dbs.isNotEmpty) {
        print('第一条 d: id=${dbs.first['id']} object=${dbs.first['object']}');
        print('第一条 raw 顶层 keys: ${dbs.first.keys.toList()}');
        print('第一条 raw title: '
            '${jsonEncode(dbs.first['title']).toString().substring(0, 200)}');
      }
    } on NotionApiException catch (e) {
      print('NotionApiException: ${e.statusCode} ${e.code} = ${e.message}');
    } catch (e) {
      print('其他异常: $e');
    }
  }, tags: ['diagnose']);

  test('E. 模拟 UI 解析: titleArr.parse + plain_text 链', () async {
    print('\n═══ E. 模拟 _fetchDatabases 解析路径 ═══');
    final body = await postSearch({
      'filter': {'value': 'data_source', 'property': 'object'},
      'page_size': 50,
    });
    final results = (body['results'] as List<dynamic>?) ?? [];
    final parsed = results.map((d) {
      final m = d as Map<String, dynamic>;
      final titleArr = m['title'] as List<dynamic>? ?? [];
      final titleText = titleArr
          .map((t) => (t['plain_text'] as String?) ?? '')
          .join()
          .trim();
      return {
        'id': m['id'],
        'object': m['object'],
        'title': titleText.isEmpty ? '(无标题)' : titleText,
      };
    }).toList();
    print('解析后数据库条目数: ${parsed.length}');
    for (final p in parsed) {
      print('  ${p}');
    }
  }, tags: ['diagnose']);
}
