// test/core/game_kit/skin/game_skin_index_persist_test.dart
//
// GameSkinBundle KV index 持久化 / 恢复单元测试（id58 + 皮肤线上化 id49）：
//   · persistIndexJson → restorePersistedIndex 往返（模拟进程重启）
//   · fetchAndMerge 成功后自动落盘
//   · 无文件 / 损坏文件 / 空 baseUrl → restore false 且不抛
//   · game-center 封面恢复后 gameCenterCoverOf 命中（id58 端到端语义）

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/file_resolver.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/game_center_skin_spec.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/game_skin_bundle.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/game_skin_localizer.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/game_skin_meta.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/game_skin_spec.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/public_kv_reader.dart';

/// 测试专用规约（不与 chess/gomoku 生产分区串味）。
const _spec = GameSkinSpec(
  gameId: 'tgame',
  displayName: 'TestGame',
  assetKeys: {'wK', 'bK'},
);

Map<String, dynamic> _fileRef(String id) => {
      'fileId': id,
      'fileName': '$id.webp',
      'sizeBytes': 8,
      'contentType': 'image/webp',
    };

String _metaJson(String id) => jsonEncode({
      'id': id,
      'displayName': 'Skin $id',
      'version': 1,
      'pieces': {'wK': _fileRef('wK-$id'), 'bK': _fileRef('bK-$id')},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('skin_index_persist_');
    GameSkinLocalizer.setBaseDirForTest(tempRoot, spec: _spec);
  });

  tearDown(() async {
    GameSkinLocalizer.setBaseDirForTest(null);
    try {
      if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
    } catch (_) {}
  });

  group('persist → restore 往返', () {
    test('persist 后新建 bundle 恢复，metas/byId 可用', () async {
      final bundle = GameSkinBundle(_spec);
      final raw = '[${_metaJson('s1')},${_metaJson('s2')}]';
      expect(await bundle.persistIndexJson(raw, baseUrl: 'http://host'), isTrue);

      // 模拟进程重启：全新 bundle 实例从磁盘恢复。
      final restored = GameSkinBundle(_spec);
      expect(await restored.restorePersistedIndex(), isTrue);
      expect(restored.metaCount, 2);
      expect(restored.byId('s1').pieces['wK'], isNotNull);
      expect(restored.byId('s2').displayName, 'Skin s2');
      // 'default' 永不碰。
      expect(restored.byId('default').pieces, isEmpty);
    });

    test('restore 覆盖同名 id（upsert 语义）', () async {
      final bundle = GameSkinBundle(_spec);
      bundle.registerRemoteSkins(
        GameSkinMeta.parseList('[${_metaJson('s1')}]'),
        fileResolver: const PublicFileResolver(baseUrl: 'http://host'),
      );
      final raw2 = '[${_metaJson('s1')}]';
      // 落盘版本 displayName 与内存一致（upsert 后仍可解析）。
      expect(await bundle.persistIndexJson(raw2, baseUrl: 'http://host'), isTrue);
      expect(await bundle.restorePersistedIndex(), isTrue);
      expect(bundle.metaCount, 1);
      expect(bundle.byId('s1').displayName, 'Skin s1');
    });
  });

  group('fetchAndMerge 自动落盘', () {
    test('KV 拉取成功 → 落盘，重置后可离线恢复', () async {
      final client = MockClient((req) async {
        expect(req.url.path, contains('/api/v1/kv/public/tgame_skin:index'));
        return http.Response(
          jsonEncode({
            'code': 0,
            'message': 'ok',
            'data': {'value': '[${_metaJson('s1')}]'},
          }),
          200,
        );
      });
      final bundle = GameSkinBundle(_spec);
      expect(
        await bundle.fetchAndMerge(
          reader: PublicKvReader(baseUrl: 'http://host', client: client),
          resolver: const PublicFileResolver(baseUrl: 'http://host'),
          defaultBaseUrl: 'http://host',
        ),
        isTrue,
      );
      // fire-and-forget 落盘 — 给真实 IO 一点时间。
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final restored = GameSkinBundle(_spec);
      expect(await restored.restorePersistedIndex(), isTrue);
      expect(restored.metaCount, 1);
      expect(restored.byId('s1').displayName, 'Skin s1');
    });
  });

  group('容错', () {
    test('无落盘文件 → restore false', () async {
      final bundle = GameSkinBundle(_spec);
      expect(await bundle.restorePersistedIndex(), isFalse);
      expect(bundle.metaCount, 0);
    });

    test('落盘文件损坏 → restore false 且不抛', () async {
      final root = await GameSkinLocalizer.ensureCacheRootFor(_spec);
      expect(root, isNotNull);
      File('${root!.path}${Platform.pathSeparator}'
              '${GameSkinBundle.kIndexCacheFileName}')
          .writeAsStringSync('{not valid json');
      final bundle = GameSkinBundle(_spec);
      expect(await bundle.restorePersistedIndex(), isFalse);
      expect(bundle.metaCount, 0);
    });

    test('wrapper 缺 baseUrl → restore false', () async {
      final root = await GameSkinLocalizer.ensureCacheRootFor(_spec);
      File('${root!.path}${Platform.pathSeparator}'
              '${GameSkinBundle.kIndexCacheFileName}')
          .writeAsStringSync(jsonEncode({'index': '[${_metaJson('s1')}]'}));
      final bundle = GameSkinBundle(_spec);
      expect(await bundle.restorePersistedIndex(), isFalse);
      expect(bundle.metaCount, 0);
    });

    test('wrapper 的 index 解析失败（id 非法）→ restore false', () async {
      final root = await GameSkinLocalizer.ensureCacheRootFor(_spec);
      final badIndex = jsonEncode([
        {
          'id': 'BAD_ID!',
          'displayName': 'x',
          'pieces': {
            'wK': _fileRef('a'),
            'bK': _fileRef('b'),
          },
        }
      ]);
      File('${root!.path}${Platform.pathSeparator}'
              '${GameSkinBundle.kIndexCacheFileName}')
          .writeAsStringSync(jsonEncode({'baseUrl': 'http://host', 'index': badIndex}));
      final bundle = GameSkinBundle(_spec);
      expect(await bundle.restorePersistedIndex(), isFalse);
      expect(bundle.metaCount, 0);
    });
  });

  group('game-center 封面（id58）', () {
    test('持久化恢复后 gameCenterCoverOf 命中 small/large', () async {
      GameSkinLocalizer.setBaseDirForTest(
        tempRoot,
        spec: kGameCenterSkinSpec,
      );
      final raw = jsonEncode([
        {
          'id': 'chess-online',
          'displayName': 'Chess',
          'version': 1,
          'pieces': {'small': _fileRef('sm'), 'large': _fileRef('lg')},
        }
      ]);
      expect(
        await gameCenterSkinBundle.persistIndexJson(
          raw,
          baseUrl: 'http://host',
        ),
        isTrue,
      );
      expect(await gameCenterSkinBundle.restorePersistedIndex(), isTrue);
      expect(gameCenterCoverOf('chess-online', 'small'), isNotNull);
      expect(gameCenterCoverOf('chess-online', 'large'), isNotNull);
      // 未上传 slug → null（程序化兜底）。
      expect(gameCenterCoverOf('not-uploaded', 'small'), isNull);
    });
  });
}
