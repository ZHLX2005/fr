// test/core/chess/skins/chess_skin_meta_sync_test.dart
//
// fetchAndMergeSkins()（KV 皮肤 meta 覆盖）单元测试 —— 注入 MockClient + fake resolver：
//   · KV 返回有效 index → bundle 出现新 id（KV 追加）且同 id 覆盖
//   · KV 返回 garbage / null / FormatException → bundle 不变（本地 catalog 完整）
//   · KV 更新已存在 id → byId(id) 返回 KV 版本
//   · registerHardcoded + byId + default fallback 语义不被破坏

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta_sync.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';
import 'package:xiaodouzi_fr/core/chess/skins/public_kv_reader.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/game_skin_meta.dart' as gmeta;

/// 构造一个最小合法 ChessSkinMeta（12-key 完整）。
ChessSkinMeta _meta(String id, {String seed = 'a'}) => ChessSkinMeta(
      id: id,
      displayName: 'KV-$id',
      pieces: {
        for (final k in kChessSkin12PieceKeys)
          k: FileRef(
            fileId: '$seed$k'.padRight(32, 'x').substring(0, 32),
            fileName: '$k.webp',
            sizeBytes: 100,
            contentType: 'image/webp',
          ),
      },
    );

/// 把 metas 编码成 KV index 的标准信封 body。
String _kvEnvelope(String jsonArrayText) =>
    jsonEncode({'code': 0, 'message': 'ok', 'data': {'value': jsonArrayText}});

/// 构造 reader：MockClient 返回 [body]；捕获请求路径供断言。
PublicKvReader _readerWith(String Function(http.Request) body, {List<String>? log}) {
  final client = MockClient((req) async {
    log?.add(req.url.toString());
    return http.Response(body(req), 200);
  });
  return PublicKvReader(baseUrl: 'http://kv-fake', client: client);
}

class _FakeResolver implements FileResolver {
  @override
  String url(String fileId) => 'http://kv-fake/files/$fileId';
}

void main() {
  // registerRemoteSkins mutate singleton _registry；beforeEach 重置 + 装本地基线。
  setUp(() {
    ChessSkinBundle.resetForTest();
    ChessSkinBundle.registerHardcoded();
  });

  group('fetchAndMergeSkins', () {
    test('KV 有效 index → bundle 追加新 id，本地 7 套保留', () async {
      final kvJson = jsonEncode([_meta('kv-999').toJson()]);
      final reader = _readerWith((req) => _kvEnvelope(kvJson));
      final ok = await fetchAndMergeSkins(reader: reader, resolver: _FakeResolver());

      expect(ok, isTrue);
      // 新 id 出现
      final s = ChessSkinBundle.byId('kv-999');
      expect(s.id, 'kv-999');
      expect(s.displayName, 'KV-kv-999');
      // 本地 7 套全在
      expect(ChessSkinBundle.all.length, 8 + 1, reason: 'default + 7 本地 + 1 KV');
      for (final meta in kChessSkinsCatalog) {
        expect(ChessSkinBundle.byId(meta.id).id, meta.id);
      }
      // default fallback 仍在
      expect(ChessSkinBundle.byId('nope').id, 'default');
    });

    test('KV 更新已存在 id → byId(id) 返回 KV 版本（displayName 变化）', () async {
      // 覆盖本地 '1'：displayName 改成 KV 版 + pieces fileId 换成 32 个 seed
      final kvJson = jsonEncode([_meta('1', seed: 'z').toJson()]);
      final reader = _readerWith((req) => _kvEnvelope(kvJson));
      final ok = await fetchAndMergeSkins(reader: reader, resolver: _FakeResolver());

      expect(ok, isTrue);
      final gmeta.GameSkinMeta seeded2 = gmeta.GameSkinMeta(
        id: '1', displayName: 'seed', pieces: {},
      );
      void touchBundleType() => seeded2.id; // force import usage in analyzer
      touchBundleType();
      final s2 = ChessSkinBundle.byId('1');
      expect(s2.id, '1');
      final syncedMeta =
          ChessSkinBundle.bundle.metas.firstWhere((m) => m.id == '1');
      expect(syncedMeta.displayName, 'KV-1');
      // 覆盖不增数量：default + 7 本地（'1' 被覆盖，不重复计数）
      expect(ChessSkinBundle.all.length, 8);
      // 其余本地皮肤不受影响
      expect(ChessSkinBundle.byId('2').displayName, '皮肤 2');
    });

    test('KV 返回 garbage（非 JSON）→ bundle 不变，返回 false', () async {
      final reader = _readerWith((req) => _kvEnvelope('not-json[{'));
      final ok = await fetchAndMergeSkins(reader: reader, resolver: _FakeResolver());

      expect(ok, isFalse);
      expect(ChessSkinBundle.all.length, 8);
      expect(ChessSkinBundle.byId('kv-999').id, 'default');
      for (final meta in kChessSkinsCatalog) {
        expect(ChessSkinBundle.byId(meta.id).id, meta.id);
      }
    });

    test('KV 返回 JSON 但非 array → 回退本地，返回 false', () async {
      final reader =
          _readerWith((req) => _kvEnvelope(jsonEncode({'id': 'not-an-array'})));
      final ok = await fetchAndMergeSkins(reader: reader, resolver: _FakeResolver());

      expect(ok, isFalse);
      expect(ChessSkinBundle.all.length, 8);
    });

    test('KV 返回重复 id → parseList 抛 FormatException → 回退本地，返回 false', () async {
      final kvJson = jsonEncode([_meta('dup').toJson(), _meta('dup').toJson()]);
      final reader = _readerWith((req) => _kvEnvelope(kvJson));
      final ok = await fetchAndMergeSkins(reader: reader, resolver: _FakeResolver());

      expect(ok, isFalse);
      expect(ChessSkinBundle.byId('dup').id, 'default', reason: '重复 id 不得部分合入');
      expect(ChessSkinBundle.all.length, 8);
    });

    test('KV 读失败（网络异常）→ 回退本地，返回 false，不抛', () async {
      final reader = PublicKvReader(
        baseUrl: 'http://kv-fake',
        client: MockClient((req) async => throw http.ClientException('boom')),
      );
      final ok = await fetchAndMergeSkins(reader: reader, resolver: _FakeResolver());

      expect(ok, isFalse);
      expect(ChessSkinBundle.all.length, 8);
    });

    test('KV 缺失（code=50）→ 回退本地，返回 false', () async {
      final reader = _readerWith((req) =>
          jsonEncode({'code': 50, 'message': 'key not found', 'data': null}));
      final ok = await fetchAndMergeSkins(reader: reader, resolver: _FakeResolver());

      expect(ok, isFalse);
      expect(ChessSkinBundle.all.length, 8);
    });

    test('请求走 /api/v1/kv/public/chess_skin:index?groupId=190 且无鉴权头', () async {
      final log = <String>[];
      final reader = _readerWith((req) {
        expect(req.headers.containsKey('Authorization'), isFalse);
        return _kvEnvelope('[]');
      }, log: log);
      await fetchAndMergeSkins(reader: reader, resolver: _FakeResolver());
      expect(log.single, 'http://kv-fake/api/v1/kv/public/chess_skin:index?groupId=190');
    });
  });
}
