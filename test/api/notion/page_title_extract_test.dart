// extractTitle 单元测试 — 解析 page JSON 里的 title（rich_text array）。

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/notion/page_endpoint.dart';

void main() {
  group('NotionPageEndpoint.extractTitle', () {
    test('提取 mention.date + 空格 标题', () {
      final page = {
        'properties': {
          '名称': {
            'id': 'title',
            'type': 'title',
            'title': [
              {
                'type': 'mention',
                'mention': {
                  'type': 'date',
                  'date': {'start': '2026-07-02T18:00:00.000+08:00'},
                },
              },
              {'type': 'text', 'text': {'content': ' '}},
            ],
          },
        },
      };
      expect(NotionPageEndpoint.extractTitle(page), '2026-07-02T18:00:00.000+08:00');
    });

    test('提取纯文本标题', () {
      final page = {
        'properties': {
          '名称': {
            'type': 'title',
            'title': [
              {'type': 'text', 'text': {'content': 'Hello '}},
              {'type': 'text', 'text': {'content': 'World'}},
            ],
          },
        },
      };
      expect(NotionPageEndpoint.extractTitle(page), 'Hello World');
    });

    test('空 title 返回占位符', () {
      final page = {
        'properties': {
          '名称': {'type': 'title', 'title': []},
        },
      };
      expect(NotionPageEndpoint.extractTitle(page), '(空标题)');
    });

    test('无 type=title 属性返回占位符', () {
      final page = {
        'properties': {
          '状态': {'type': 'select'},
        },
      };
      expect(NotionPageEndpoint.extractTitle(page), '(无标题)');
    });

    test('properties 为 null 返回占位符', () {
      expect(NotionPageEndpoint.extractTitle({}), '(无标题)');
    });
  });
}