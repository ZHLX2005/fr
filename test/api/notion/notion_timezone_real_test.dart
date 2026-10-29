// ignore_for_file: avoid_print
// 本文件是诊断 / e2e 链路脚本，控制台输出即测试结果本身，
// 不属于 avoid_print 所指的「生产代码」。
// 验证 Notion date mention 时区修复 — 用 -08:00 后缀让显示变成本地时间。

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'notion_test_helpers.dart';

void main() {
  test('对比 3 种 ISO 字符串的 Notion date mention 显示', () async {
    final token = requireTestToken();
    final headers = {
      'Authorization': 'Bearer $token',
      'Notion-Version': '2022-06-28',
      'Content-Type': 'application/json',
    };

    Future<Map<String, dynamic>> create(String label, String iso) async {
      final body = jsonEncode({
        'parent': {'database_id': testDatabaseId},
        'properties': {
          '名称': {
            'title': [
              {
                'type': 'mention',
                'mention': {'type': 'date', 'date': {'start': iso}},
              },
              {'type': 'text', 'text': {'content': ' TZ_TEST_$label '}},
            ],
          },
        },
      });
      final resp = await http.post(
        Uri.parse('https://api.notion.com/v1/pages'),
        headers: headers,
        body: body,
      );
      if (resp.statusCode >= 400) {
        throw Exception('Notion error ${resp.statusCode}: ${resp.body}');
      }
      return jsonDecode(resp.body);
    }

    final noTz = DateTime.now().toIso8601String();
    final minus8 = '$noTz-08:00';
    final plus8 = '$noTz+08:00';

    print('当前北京时间: ${DateTime.now()}');

    print('--- 1. 无时区 ($noTz) ---');
    final p1 = await create('A', noTz);
    final t1 = (p1['properties']['名称']['title'] as List).first;
    print('   date.start: ${t1['mention']['date']['start']}');
    print('   plain_text: ${t1['plain_text']}');

    print('--- 2. -08:00 ($minus8) ---');
    final p2 = await create('B', minus8);
    final t2 = (p2['properties']['名称']['title'] as List).first;
    print('   date.start: ${t2['mention']['date']['start']}');
    print('   plain_text: ${t2['plain_text']}');

    print('--- 3. +08:00 ($plus8) ---');
    final p3 = await create('C', plus8);
    final t3 = (p3['properties']['名称']['title'] as List).first;
    print('   date.start: ${t3['mention']['date']['start']}');
    print('   plain_text: ${t3['plain_text']}');

    // 期望：#2 (-08:00 后缀) 显示成「当前北京时间 + TZ_TEST_B」
    print('');
    print('结论：对比 plain_text，找到最接近当前北京时间的那个');
  });
}