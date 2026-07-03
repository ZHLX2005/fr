import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/schema/fr_uri.dart';

void main() {
  group('FrUri.tryParse', () {
    test('parses simple host-only URL', () {
      final uri = FrUri.tryParse('fr://lab');
      expect(uri, isNotNull);
      expect(uri!.scheme, 'fr');
      expect(uri.authority, 'lab');
      expect(uri.path, '');
      expect(uri.query, isEmpty);
    });

    test('parses multi-segment authority (lab/demo/clock)', () {
      final uri = FrUri.tryParse('fr://lab/demo/clock');
      expect(uri, isNotNull);
      expect(uri!.authority, 'lab/demo/clock');
      expect(uri.path, 'demo/clock');
    });

    test('parses notion/image-host (sub-authority)', () {
      final uri = FrUri.tryParse('fr://notion/image-host');
      expect(uri, isNotNull);
      expect(uri!.authority, 'notion/image-host');
      expect(uri.path, 'image-host');
    });

    test('parses query string with single key', () {
      final uri = FrUri.tryParse('fr://notion/image-host?autocapture=true');
      expect(uri, isNotNull);
      expect(uri!.authority, 'notion/image-host');
      expect(uri.path, 'image-host');
      expect(uri.query['autocapture'], 'true');
    });

    test('parses query string with multiple keys', () {
      final uri = FrUri.tryParse('fr://x?a=1&b=2');
      expect(uri, isNotNull);
      expect(uri!.authority, 'x');
      expect(uri.query['a'], '1');
      expect(uri.query['b'], '2');
    });

    test('returns null for non-fr scheme', () {
      expect(FrUri.tryParse('http://lab'), isNull);
      expect(FrUri.tryParse('https://x.com'), isNull);
    });

    test('returns null for empty string', () {
      expect(FrUri.tryParse(''), isNull);
    });

    test('handles URL-encoded path segments', () {
      final uri = FrUri.tryParse('fr://lab/demo/%E6%97%85%E8%A1%8C');
      expect(uri, isNotNull);
      expect(uri!.authority, 'lab/demo/旅行');
      expect(uri.path, 'demo/旅行');
    });

    test('原始中文 URL 不崩（Uri.decodeComponent 容错回归保护）', () {
      // 历史 bug：Uri.decodeComponent 对原始中文字符串抛 Illegal percent encoding，
      // 导致 fr://lab/demo/时钟 等含中文 URL 全部 resolve 崩溃。
      // safeDecode 修复后，原始中文应原样保留、不抛异常。
      final uri = FrUri.tryParse('fr://lab/demo/时钟');
      expect(uri, isNotNull);
      expect(uri!.authority, 'lab/demo/时钟');
      expect(uri.path, 'demo/时钟');

      // query 含原始中文也应容错
      final uri2 = FrUri.tryParse('fr://x?name=时钟');
      expect(uri2, isNotNull);
      expect(uri2!.query['name'], '时钟');
    });

    test('非法百分号序列容错（不抛异常，原样返回）', () {
      // '%ZZ' 不是合法十六进制，safeDecode 应吞异常返回原串
      final uri = FrUri.tryParse('fr://lab/%ZZ');
      expect(uri, isNotNull);
      expect(uri!.authority, 'lab/%ZZ');
    });
  });
}
