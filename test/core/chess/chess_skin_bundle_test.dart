import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/remote_chess_skin.dart';

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
}