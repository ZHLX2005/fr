import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/ai_gallery/ai_gallery_log.dart';
import 'package:xiaodouzi_fr/lab/demos/ai_gallery/ai_gallery_models.dart';
import 'package:xiaodouzi_fr/lab/demos/ai_gallery/ai_gallery_prompt.dart';
import 'package:xiaodouzi_fr/lab/demos/ai_gallery/ai_gallery_settings.dart';

void main() {
  group('buildGalleryRetryPrompt', () {
    test('保留原提示词，并带上错误回执与上一次的原始回复', () {
      final p = buildGalleryRetryPrompt(
        basePrompt: '分析这张图，输出 JSON',
        attempt: 1,
        error: 'JSON 语法错误：Unexpected character',
        previousReply: '{"title": "电梯"',
      );
      expect(p, contains('分析这张图，输出 JSON'));
      expect(p, contains('第 1 次重试'));
      expect(p, contains('JSON 语法错误：Unexpected character'));
      expect(p, contains('{"title": "电梯"'));
      expect(p, contains('不要 markdown'));
      // 原提示词必须在最前，避免多轮重试后模型丢掉原始契约
      expect(p.startsWith('分析这张图，输出 JSON'), isTrue);
    });

    test('没有回复内容时说明请求失败，不回填空节选', () {
      final p = buildGalleryRetryPrompt(
        basePrompt: 'p',
        attempt: 2,
        error: 'timeout',
      );
      expect(p, contains('没有拿到任何回复'));
      expect(p, isNot(contains('<<<')));
    });

    test('超长回复按 snippetChars 截断', () {
      final p = buildGalleryRetryPrompt(
        basePrompt: 'p',
        attempt: 1,
        error: 'e',
        previousReply: 'x' * 100,
        snippetChars: 10,
      );
      expect(p, contains('x' * 10));
      expect(p, isNot(contains('x' * 11)));
      expect(p, contains('后略'));
    });

    test('多行错误被压成一行', () {
      final p = buildGalleryRetryPrompt(
        basePrompt: 'p',
        attempt: 1,
        error: 'Error\n  at line 1\n  at line 2',
      );
      expect(p, contains('Error at line 1 at line 2'));
    });
  });

  group('parseAiJson 的错误日志', () {
    test('没有 JSON 对象时带可读原因与原始回复', () {
      expect(
        () => parseAiJson('这张图我看出不来'),
        throwsA(
          isA<AiGalleryParseException>()
              .having((e) => e.detail, 'detail', contains('找不到'))
              .having((e) => e.rawReply, 'rawReply', '这张图我看出不来'),
        ),
      );
    });

    test('空回复不抛裸 FormatException', () {
      expect(
        () => parseAiJson('   '),
        throwsA(
          isA<AiGalleryParseException>().having(
            (e) => e.detail,
            'detail',
            contains('为空'),
          ),
        ),
      );
    });

    test('语法错误带定位信息', () {
      expect(
        () => parseAiJson('{"title": }'),
        throwsA(
          isA<AiGalleryParseException>().having(
            (e) => e.detail,
            'detail',
            contains('JSON 语法错误'),
          ),
        ),
      );
    });

    test('数组等非对象回复也给出可读原因', () {
      expect(
        () => parseAiJson('[1,2,3]'),
        throwsA(
          isA<AiGalleryParseException>().having(
            (e) => e.detail,
            'detail',
            contains('找不到完整的 JSON 对象'),
          ),
        ),
      );
    });

    test('describeAiError 对解析异常给出 detail', () {
      final e = AiGalleryParseException('坏了', rawReply: 'x');
      expect(describeAiError(e), '坏了');
    });
  });

  group('AiGallerySettings 持久化字段', () {
    test('key / 模型 / 重试 / 日志配置编解码后不丢', () {
      const s = AiGallerySettings(
        protocolId: 'anthropic',
        baseUrl: 'https://api.anthropic.com',
        apiKey: 'sk-ant-123',
        model: 'claude-sonnet-4-6',
        prompt: '自定义',
        scanCount: 24,
        maxConcurrency: 3,
        autoScan: true,
        retryCount: 4,
        logEnabled: true,
        logMaxEntries: 500,
        logMaxChars: 800,
      );
      final back = AiGallerySettings.decode(AiGallerySettings.encode(s));
      expect(back.protocolId, 'anthropic');
      expect(back.apiKey, 'sk-ant-123');
      expect(back.model, 'claude-sonnet-4-6');
      expect(back.prompt, '自定义');
      expect(back.scanCount, 24);
      expect(back.maxConcurrency, 3);
      expect(back.retryCount, 4);
      expect(back.logEnabled, isTrue);
      expect(back.logMaxEntries, 500);
      expect(back.logMaxChars, 800);
    });

    test('旧版本遗留的 JSON（无新字段）走默认值', () {
      final back = AiGallerySettings.decode('{"apiKey":"k","model":"m"}');
      expect(back.apiKey, 'k');
      expect(back.retryCount, 2);
      expect(back.logEnabled, isFalse);
      expect(back.prompt, kDefaultGalleryPrompt);
    });

    test('isConfigured 依赖地址/key/模型三项', () {
      expect(const AiGallerySettings().isConfigured, isFalse);
      expect(
        const AiGallerySettings(
          baseUrl: 'u',
          apiKey: 'k',
          model: 'm',
        ).isConfigured,
        isTrue,
      );
    });
  });

  group('AiGalleryLog 按配置长度记录', () {
    setUp(() {
      AiGalleryLog.instance
        ..configure(enabled: true, maxEntries: 20, maxChars: 80)
        ..clear();
    });

    test('关闭时不记录', () {
      AiGalleryLog.instance
        ..configure(enabled: false)
        ..clear()
        ..info('t', 'x');
      expect(AiGalleryLog.instance.entries, isEmpty);
    });

    test('条数超上限丢最旧的', () {
      final log = AiGalleryLog.instance..configure(maxEntries: 20);
      for (var i = 0; i < 25; i++) {
        log.info('t', 'm$i');
      }
      expect(log.entries.length, 20);
      expect(log.entries.first.message, 'm5');
      expect(log.entries.last.message, 'm24');
    });

    test('单条超长按 maxChars 截断并标记', () {
      final log = AiGalleryLog.instance..configure(maxChars: 80);
      log.info('t', 'x' * 200);
      final e = log.entries.single;
      expect(e.truncated, isTrue);
      expect(e.message.length, 81); // 80 字 + 省略号
      expect(e.message.endsWith('…'), isTrue);
    });

    test('错误计数与导出文本', () {
      final log = AiGalleryLog.instance
        ..clear()
        ..error('解析失败', 'boom')
        ..info('扫描', 'ok');
      expect(log.errorCount, 1);
      final text = log.exportText();
      expect(text, contains('[ERR][解析失败] boom'));
      expect(text, contains('[INF][扫描] ok'));
    });
  });
}
