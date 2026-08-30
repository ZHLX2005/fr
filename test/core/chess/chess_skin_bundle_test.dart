import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';
import 'package:xiaodouzi_fr/core/chess/skins/remote_chess_skin.dart';

class _FakeResolver implements FileResolver {
  @override
  String url(String fileId) => 'http://fake/files/$fileId';
}

/// 构造最小完整 12-key 的 KV meta（新皮肤）。
ChessSkinMeta _kvMeta(String id, {String displayName = 'KV'}) => ChessSkinMeta(
      id: id,
      displayName: displayName,
      pieces: {
        for (final k in kChessSkin12PieceKeys)
          k: FileRef(
            fileId: k.padRight(32, 'a'),
            fileName: '$k.webp',
            sizeBytes: 1,
            contentType: 'image/webp',
          ),
      },
    );

void main() {
  // 重要：registerHardcoded 会 mutate singleton _registry；beforeEach 重置
  setUp(() => ChessSkinBundle.resetForTest());

  group('ChessSkinBundle', () {
    test('default 永远存在（未注册时 byId("x") 仍可拿到 default）', () {
      // 不调 registerHardcoded
      final s = ChessSkinBundle.byId('nonexistent');
      expect(s.id, 'default');
      expect(s, isA<ChessDefaultSkin>());
    });

    test('registerHardcoded 后 7 套都能 byId 拿到', () {
      ChessSkinBundle.registerHardcoded();
      expect(kChessSkinsCatalog.length, 7);
      for (final meta in kChessSkinsCatalog) {
        final s = ChessSkinBundle.byId(meta.id);
        expect(s, isA<RemoteChessSkin>());
        expect(s.id, meta.id);
      }
    });

    test('RemoteChessSkin 拼 URL 用 chess_skin_meta 的 baseUrl 默认值', () {
      ChessSkinBundle.registerHardcoded();
      final s = ChessSkinBundle.byId('1') as RemoteChessSkin;
      // pieces 第一项 URL 必须以 default baseUrl 起
      final firstUrl = (s.pieces['wK']! as CachedNetworkImageProvider).url;
      expect(firstUrl.startsWith('http://'), true);
      expect(firstUrl.contains('/files/'), true);
      expect(firstUrl.endsWith('0f6a7d9256a248309fa249e58724a351'), true);
    });

    test('all() 含 default + 7 套共 8 个', () {
      ChessSkinBundle.registerHardcoded();
      expect(ChessSkinBundle.all.length, 8);
      expect(ChessSkinBundle.all.keys.contains('default'), true);
    });
  });

  // ─────────────── metas（Fix A：live 皮肤列表数据源） ───────────────

  group('ChessSkinBundle.metas', () {
    test('resetForTest 清空 metas', () {
      ChessSkinBundle.registerHardcoded();
      expect(ChessSkinBundle.metaCount, 7);
      ChessSkinBundle.resetForTest();
      expect(ChessSkinBundle.metaCount, 0);
      expect(ChessSkinBundle.metas, isEmpty);
    });

    test('registerHardcoded → metas = 7 本地（catalog 顺序）', () {
      ChessSkinBundle.registerHardcoded();
      expect(ChessSkinBundle.metaCount, 7);
      final ids = ChessSkinBundle.metas.map((m) => m.id).toList();
      expect(ids, kChessSkinsCatalog.map((m) => m.id).toList(),
          reason: '本地 7 套按 catalog 顺序');
      // 与注册表一一对应（不重复 / 不缺）
      for (final meta in ChessSkinBundle.metas) {
        expect(ChessSkinBundle.byId(meta.id).id, meta.id);
      }
    });

    test('registerRemoteSkins([新 id]) → metas 8，新 id 在末尾', () {
      ChessSkinBundle.registerHardcoded();
      ChessSkinBundle.registerRemoteSkins(
        [_kvMeta('kv-999')],
        fileResolver: _FakeResolver(),
      );
      expect(ChessSkinBundle.metaCount, 8);
      final ids = ChessSkinBundle.metas.map((m) => m.id).toList();
      expect(ids.last, 'kv-999', reason: 'KV 新 id 追加到列表末尾');
      expect(ids.take(7), kChessSkinsCatalog.map((m) => m.id).toList());
    });

    test('覆盖同 id → metas 数量不变，顺序保持原位', () {
      ChessSkinBundle.registerHardcoded();
      // 覆盖 catalog 的 '1'：displayName 变 KV 版
      ChessSkinBundle.registerRemoteSkins(
        [_kvMeta('1', displayName: 'KV-1')],
        fileResolver: _FakeResolver(),
      );
      expect(ChessSkinBundle.metaCount, 7, reason: '覆盖不增数量');
      final metas = ChessSkinBundle.metas;
      expect(metas.first.id, '1', reason: '同 id 覆盖保位（仍在首位）');
      expect(metas.first.displayName, 'KV-1');
      // 注册表同步为 KV 版本
      expect(ChessSkinBundle.byId('1').displayName, 'KV-1');
    });

    test('多个新 id 按注册顺序追加', () {
      ChessSkinBundle.registerHardcoded();
      ChessSkinBundle.registerRemoteSkins(
        [_kvMeta('a-new'), _kvMeta('b-new')],
        fileResolver: _FakeResolver(),
      );
      final ids = ChessSkinBundle.metas.map((m) => m.id).toList();
      expect(ids.sublist(7), ['a-new', 'b-new']);
    });
  });
}