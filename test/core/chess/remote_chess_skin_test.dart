import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';
import 'package:xiaodouzi_fr/core/chess/skins/remote_chess_skin.dart';

class _FakeResolver implements FileResolver {
  final String prefix;
  _FakeResolver({this.prefix = 'http://fake'});
  @override
  String url(String fileId) => '$prefix/files/$fileId';
}

void main() {
  // 用一个最小完整 ChessSkinMeta 跑测试
  ChessSkinMeta meta({FileRef? board}) {
    return ChessSkinMeta(
      id: 't',
      displayName: 'T',
      pieces: {
        for (final k in kChessSkin12PieceKeys)
          k: FileRef(
              fileId: '${k}_fid'.padRight(32, 'a'),
              fileName: '$k.webp',
              sizeBytes: 100,
              contentType: 'image/webp'),
      },
      boardBackground: board,
    );
  }

  test('pieces[k] 是 CachedNetworkImageProvider + URL 是 resolver.url(fid)', () {
    final s = RemoteChessSkin(
        meta: meta(), fileResolver: _FakeResolver(prefix: 'http://fake'));
    expect(s, isA<ChessSkin>());
    final img = s.pieces['wK']!;
    expect(img, isA<CachedNetworkImageProvider>());
    expect((img as CachedNetworkImageProvider).url, 'http://fake/files/wK_fidaaaaaaaaaaaaaaaaaaaaaaaaaa');
  });

  test('12 个 piece 全部映射，key 完整', () {
    final s = RemoteChessSkin(meta: meta(), fileResolver: _FakeResolver());
    expect(s.pieces.keys.toSet(), kChessSkin12PieceKeys);
  });

  test('boardBackground = null → boardBackground getter = null', () {
    final s = RemoteChessSkin(meta: meta(board: null), fileResolver: _FakeResolver());
    expect(s.boardBackground, isNull);
  });

  test('boardBackground 非空 → wrapped CachedNetworkImageProvider', () {
    final board = FileRef(
        fileId: 'b' * 32, fileName: 'board.png', sizeBytes: 32768, contentType: 'image/png');
    final s = RemoteChessSkin(meta: meta(board: board), fileResolver: _FakeResolver());
    final img = s.boardBackground!;
    expect(img, isA<CachedNetworkImageProvider>());
    expect((img as CachedNetworkImageProvider).url, 'http://fake/files/${'b' * 32}');
  });
}
