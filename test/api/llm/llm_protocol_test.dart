import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/api/llm/llm.dart';
import 'package:xiaodouzi_fr/lab/demos/ai_gallery/ai_gallery_models.dart';

void main() {
  group('OpenAiProtocol', () {
    const protocol = OpenAiProtocol();

    test('buildUrl 拼接 /v1/chat/completions 并容忍尾部斜杠', () {
      expect(
        protocol.buildUrl('https://api.openai.com/').toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        protocol.buildUrl('https://relay.example.com/v1').toString(),
        'https://relay.example.com/v1/chat/completions',
      );
    });

    test('buildHeaders 用 Bearer', () {
      expect(protocol.buildHeaders('sk-test')['Authorization'],
          'Bearer sk-test');
    });

    test('buildBody 纯文本退化为 content 字符串', () {
      final body = protocol.buildBody(
        model: 'gpt-4o-mini',
        systemPrompt: 'sys',
        messages: const [LlmChatMessage(text: 'hi')],
      );
      final messages = body['messages'] as List;
      expect(messages[0]['role'], 'system');
      expect(messages[1]['content'], 'hi');
      expect(body['model'], 'gpt-4o-mini');
    });

    test('buildBody 带图片时走 image_url data URL', () {
      final body = protocol.buildBody(
        model: 'gpt-4o-mini',
        systemPrompt: '',
        messages: const [
          LlmChatMessage(
            text: '描述这张图',
            images: [LlmImage(base64Data: 'QUJD', mediaType: 'image/jpeg')],
          ),
        ],
      );
      final messages = body['messages'] as List;
      // 无 system prompt → messages 只有 user 一条
      expect(messages.length, 1);
      final content = messages[0]['content'] as List;
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'image_url');
      expect(
        (content[1]['image_url'] as Map)['url'],
        'data:image/jpeg;base64,QUJD',
      );
    });

    test('buildBody 空模型名抛 LlmRequestException', () {
      expect(
        () => protocol.buildBody(
            model: '', systemPrompt: '', messages: const []),
        throwsA(isA<LlmRequestException>()),
      );
    });

    test('parseResponse 提取 choices[0].message.content', () {
      final result = protocol.parseResponse({
        'model': 'gpt-4o-mini',
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'hello'},
          },
        ],
      });
      expect(result.text, 'hello');
      expect(result.model, 'gpt-4o-mini');
    });
  });

  group('AnthropicProtocol', () {
    const protocol = AnthropicProtocol();

    test('buildUrl 拼接 /v1/messages', () {
      expect(
        protocol.buildUrl('https://api.anthropic.com').toString(),
        'https://api.anthropic.com/v1/messages',
      );
    });

    test('buildHeaders 用 x-api-key + anthropic-version', () {
      final headers = protocol.buildHeaders('ak-test');
      expect(headers['x-api-key'], 'ak-test');
      expect(headers['anthropic-version'], isNotEmpty);
    });

    test('buildBody system 独立 + 图片走 base64 source + max_tokens 必填', () {
      final body = protocol.buildBody(
        model: 'claude-sonnet-4-6',
        systemPrompt: 'sys prompt',
        messages: const [
          LlmChatMessage(
            text: '描述这张图',
            images: [LlmImage(base64Data: 'QUJD', mediaType: 'image/png')],
          ),
        ],
        maxTokens: null,
      );
      expect(body['system'], 'sys prompt');
      // max_tokens 未配置时给保守默认
      expect(body['max_tokens'], 1024);
      final messages = body['messages'] as List;
      expect(messages[0]['role'], 'user');
      final content = messages[0]['content'] as List;
      expect(content[0]['type'], 'image');
      final source = content[0]['source'] as Map;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/png');
      expect(source['data'], 'QUJD');
      expect(content[1], {'type': 'text', 'text': '描述这张图'});
    });

    test('parseResponse 拼接多个 text 块、跳过非 text 块', () {
      final result = protocol.parseResponse({
        'model': 'claude-sonnet-4-6',
        'content': [
          {'type': 'thinking', 'thinking': 'hidden'},
          {'type': 'text', 'text': 'part1'},
          {'type': 'text', 'text': 'part2'},
        ],
      });
      expect(result.text, 'part1part2');
    });
  });

  group('LlmEndpoint.chat', () {
    test('非 2xx 抛 LlmApiException 且消息取自 error.message', () async {
      final endpoint = LlmEndpoint(
        client: _MockClient(
          statusCode: 401,
          body: jsonEncode({
            'error': {'message': 'invalid api key'},
          }),
        ),
      );
      await expectLater(
        endpoint.chat(
          protocolId: 'openai',
          baseUrl: 'https://api.openai.com',
          apiKey: 'k',
          model: 'gpt-4o-mini',
          systemPrompt: '',
          messages: const [LlmChatMessage(text: 'hi')],
        ),
        throwsA(
          isA<LlmApiException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'invalid api key'),
        ),
      );
    });

    test('空 baseUrl / apiKey / 协议回退', () async {
      final endpoint = LlmEndpoint(client: _MockClient(statusCode: 200, body: ''));
      // 空 baseUrl → LlmRequestException，不发请求
      await expectLater(
        endpoint.chat(
          protocolId: 'openai',
          baseUrl: '',
          apiKey: 'k',
          model: 'm',
          systemPrompt: '',
          messages: const [],
        ),
        throwsA(isA<LlmRequestException>()),
      );
      // 未知协议 id 回退 OpenAI（不抛协议查找错误）
      expect(LlmEndpoint.protocolById('unknown'), isA<OpenAiProtocol>());
    });
  });

  group('parseAiJson', () {
    test('纯 JSON', () {
      final r = parseAiJson('{"title":"a"}');
      expect(r['title'], 'a');
    });

    test('markdown 代码块包裹', () {
      final r = parseAiJson('```json\n{"title":"b"}\n```');
      expect(r['title'], 'b');
    });

    test('JSON 前后有解释文字', () {
      final r = parseAiJson('好的，以下是结果：\n{"title":"c"}\n希望有帮助');
      expect(r['title'], 'c');
    });

    test('无 JSON 抛 FormatException', () {
      expect(() => parseAiJson('没有结构'), throwsA(isA<FormatException>()));
    });

    test('AiScanResult 标准/额外字段拆分', () {
      final result = AiScanResult.fromAiJson(assetId: 'x1', fields: {
        'title': '电梯间',
        'description': '一张电梯照片',
        'group': '照片',
        'tags': ['电梯', '室内'],
        'importance': 'high',
        'location': '3 号楼',
        'extra_list': ['a', 'b'],
      });
      expect(result.isImportant, isTrue);
      expect(result.tags, ['电梯', '室内']);
      expect(result.extraFields.keys, unorderedEquals(['location', 'extra_list']));
    });
  });
}

/// 最小 http.Client stub。
class _MockClient implements http.Client {
  final int statusCode;
  final String body;

  _MockClient({required this.statusCode, required this.body});

  @override
  Future<http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    return http.Response(this.body, statusCode);
  }

  @override
  void close() {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
