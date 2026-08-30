// test/core/chess/skins/public_kv_reader_test.dart
//
// PublicKvReader（匿名 public KV 读）单元测试 —— 用 http/testing MockClient：
//   · 200 + code=0 + data.value → readString 返回 value 字符串
//   · 200 + code=50（private / key 缺失）→ 返回 null
//   · 200 + body 不是标准信封 → 返回 null
//   · 非 200（500）→ 返回 null
//   · 网络异常（ClientException）→ 返回 null（不抛）
//   · 超时（永不完成的 MockClient）→ 返回 null（不抛）
//   · URL 正确：/api/v1/kv/public/<key>?groupId=<gid>

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/skins/public_kv_reader.dart';

/// 构造标准信封 body。
String _envelope({int code = 0, Object? data}) =>
    jsonEncode({'code': code, 'message': code == 0 ? 'ok' : 'key not found', 'data': data});

void main() {
  group('PublicKvReader.readString', () {
    test('200 + code=0 + data.value → 返回 value', () async {
      final client = MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/api/v1/kv/public/chess_skin:index');
        expect(req.url.queryParameters['groupId'], '190');
        expect(req.headers.containsKey('Authorization'), isFalse,
            reason: 'public 读必须无鉴权头');
        return http.Response(
          _envelope(data: {'key': 'chess_skin:index', 'value': '["skin"]', 'visibility': 'public'}),
          200,
        );
      });
      final reader = PublicKvReader(baseUrl: 'http://fake', client: client);
      expect(await reader.readString('chess_skin:index'), '["skin"]');
    });

    test('200 + code=50（private / key 缺失）→ null', () async {
      final client = MockClient(
          (req) async => http.Response(_envelope(code: 50, data: null), 200));
      final reader = PublicKvReader(baseUrl: 'http://fake', client: client);
      expect(await reader.readString('chess_skin:index'), isNull);
    });

    test('200 + body 不是标准信封（不是 Map / 缺 data.value）→ null', () async {
      final client = MockClient(
          (req) async => http.Response(jsonEncode({'foo': 'bar'}), 200));
      final reader = PublicKvReader(baseUrl: 'http://fake', client: client);
      expect(await reader.readString('chess_skin:index'), isNull);
    });

    test('非 200（500）→ null', () async {
      final client = MockClient((req) async => http.Response('oops', 500));
      final reader = PublicKvReader(baseUrl: 'http://fake', client: client);
      expect(await reader.readString('chess_skin:index'), isNull);
    });

    test('网络异常（ClientException）→ null（不抛）', () async {
      final client = MockClient(
          (req) async => throw http.ClientException('Network is unreachable'));
      final reader = PublicKvReader(baseUrl: 'http://fake', client: client);
      expect(await reader.readString('chess_skin:index'), isNull);
    });

    test('超时（永不完成）→ null（不抛，短超时兜底）', () async {
      final neverCompletes = MockClient(
          (req) => Completer<http.Response>().future);
      final reader = PublicKvReader(
        baseUrl: 'http://fake',
        client: neverCompletes,
        timeout: const Duration(milliseconds: 50),
      );
      expect(await reader.readString('chess_skin:index'), isNull);
    });

    test('baseUrl 尾斜杠归一化 + groupId 透传', () async {
      String? capturedUrl;
      final client = MockClient((req) async {
        capturedUrl = req.url.toString();
        return http.Response(_envelope(data: {'value': 'x'}), 200);
      });
      final reader = PublicKvReader(
        baseUrl: 'http://fake/',
        groupId: 7,
        client: client,
      );
      expect(await reader.readString('k'), 'x');
      expect(capturedUrl, 'http://fake/api/v1/kv/public/k?groupId=7');
    });
  });
}
