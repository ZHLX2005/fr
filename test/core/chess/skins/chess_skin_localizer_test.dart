// test/core/chess/skins/chess_skin_localizer_test.dart
//
// ChessSkinLocalizer（皮肤本地化器）单元测试 —— 用 MockClient + 临时目录：
//   · download 成功 → 12 张棋子 + boardBackground + done 标记落盘
//   · isCached 在下载前 false、下载后 true
//   · fromCache 返回 LocalChessSkin（12 pieces + boardBackground，FileImage）
//   · download 幂等（重复下载重建目录，不残留旧文件）
//   · 下载失败（HTTP 500）→ 抛异常 + 无部分缓存残留（isCached false）
//   · 网络异常（ClientException）→ 抛异常 + 目录被清理
//   · 棋盘底图扩展名由 contentType 推导（png / webp）
//
// 注入：dirProvider → Directory.systemTemp.createTemp（不碰 path_provider）。
// 目标目录结构：<tempRoot>/chess_skins/<skinId>/

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_localizer.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';
import 'package:xiaodouzi_fr/core/chess/skins/local_chess_skin.dart';

/// 1x1 有效 PNG（最小合法 png 头 + 内容），用于写入本地文件的字节。
final Uint8List _tinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _FakeResolver implements FileResolver {
  @override
  String url(String fileId) => 'http://fake/files/$fileId';
}

/// 构造完整 12-key 的 ChessSkinMeta。
ChessSkinMeta makeMeta({FileRef? board}) {
  return ChessSkinMeta(
    id: 't1',
    displayName: 'T1',
    pieces: {
      for (final k in kChessSkin12PieceKeys)
        k: FileRef(
          fileId: '${k}_fid'.padRight(32, 'a'),
          fileName: '$k.webp',
          sizeBytes: 100,
          contentType: 'image/webp',
        ),
    },
    boardBackground: board,
  );
}

/// 默认 MockClient：全部 200 返回 [bytes]。
MockClient okClient([Uint8List? bytes]) {
  final body = bytes ?? _tinyPng;
  return MockClient((req) async => http.Response.bytes(body, 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('chess_skin_localizer_');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  /// 目标皮肤目录：<tempRoot>/chess_skins/t1
  Directory skinDir() => Directory('${tempRoot.path}/chess_skins/t1');

  File skinFile(String name) => File('${skinDir().path}/$name');

  ChessSkinLocalizer makeLocalizer({http.Client? client, ChessSkinMeta? meta}) {
    return ChessSkinLocalizer(
      resolver: _FakeResolver(),
      client: client,
      dirProvider: () async => tempRoot,
      // 测试皮肤 id 't1' 不在 const catalog → 注入自定义 meta 解析。
      // [meta] 传给 isCached/fromCache 用的 meta（默认无 boardBackground）。
      metaById: (id) => id == 't1' ? (meta ?? makeMeta()) : null,
    );
  }

  test(
    'download 成功 → 12 棋子 + done 标记 + boardBackground 落盘，isCached true',
    () async {
      final l = makeLocalizer(client: okClient());
      final meta = makeMeta(
        board: FileRef(
          fileId: 'b' * 32,
          fileName: 'board.webp',
          sizeBytes: 2048,
          contentType: 'image/webp',
        ),
      );

      expect(await l.isCached('t1'), isFalse, reason: '下载前不应命中缓存');

      final skin = await l.download(meta);
      expect(skin, isA<LocalChessSkin>());
      expect(skin.id, 't1');

      // 目录内容：12 张棋子 + boardBackground.webp + .done = 14 个文件
      final files = skinDir().listSync().toList();
      expect(files, hasLength(14), reason: '12 棋子 + 棋盘底图 + done 哨兵');
      expect(skinFile('.done').existsSync(), isTrue);

      for (final key in kChessSkin12PieceKeys) {
        final f = skinFile('$key.webp');
        expect(f.existsSync(), isTrue, reason: '棋子 $key 应落盘');
        expect(f.readAsBytesSync(), _tinyPng, reason: '内容应与下载字节一致');
      }
      expect(skinFile('boardBackground.webp').existsSync(), isTrue);

      expect(await l.isCached('t1'), isTrue, reason: '下载完成后应命中缓存');
      expect(await l.isCached('nope'), isFalse, reason: '未下载皮肤不命中');
    },
  );

  test(
    'fromCache → LocalChessSkin（12 pieces + boardBackground，均为 FileImage）',
    () async {
      final l = makeLocalizer(client: okClient());
      await l.download(makeMeta(board: null));

      final cached = await l.fromCache('t1');
      expect(cached, isNotNull);
      expect(cached!.id, 't1');
      expect(cached.pieces.keys.toSet(), kChessSkin12PieceKeys);
      for (final img in cached.pieces.values) {
        expect(img, isA<FileImage>(), reason: '本地皮肤必须是 FileImage');
      }
      expect(
        cached.boardBackground,
        isNull,
        reason: '无 boardBackground → null',
      );
    },
  );

  test('fromCache 未下载 → null', () async {
    final l = makeLocalizer(client: okClient());
    expect(await l.fromCache('nope'), isNull);
  });

  test('download 幂等：重复下载重建目录，不残留旧文件', () async {
    final l = makeLocalizer(client: okClient());
    final meta = makeMeta(board: null);
    // 第一次下载
    await l.download(meta);
    // 手动塞一个"旧垃圾文件"模拟残留
    skinFile('stale.bin').writeAsBytesSync([1, 2, 3]);
    expect(
      await l.isCached('t1'),
      isTrue,
      reason: '多一个文件不影响 isCached（12 棋子 + done 都在）',
    );

    // 第二次下载（无 boardBackground）→ 目录重建
    await l.download(meta);
    final files = skinDir()
        .listSync()
        .map((e) => e.uri.pathSegments.last)
        .toList();
    expect(files.contains('stale.bin'), isFalse, reason: '重建目录应清掉残留');
    expect(files, hasLength(13), reason: '12 棋子 + done（无棋盘底图）');
  });

  test('下载失败（HTTP 500）→ 抛异常 + 无部分缓存残留（isCached false）', () async {
    final failing = MockClient((req) async => http.Response('oops', 500));
    final l = makeLocalizer(client: failing);

    await expectLater(
      l.download(makeMeta(board: null)),
      throwsA(isA<HttpException>()),
    );
    expect(await l.isCached('t1'), isFalse, reason: '失败后不得命中缓存');
    expect(skinDir().existsSync(), isFalse, reason: '失败后目录应被清理');
  });

  test('网络异常（ClientException）→ 抛异常 + 目录被清理', () async {
    final throwing = MockClient(
      (req) async => throw http.ClientException('Network is unreachable'),
    );
    final l = makeLocalizer(client: throwing);

    await expectLater(
      l.download(makeMeta(board: null)),
      throwsA(isA<http.ClientException>()),
    );
    expect(await l.isCached('t1'), isFalse);
    expect(skinDir().existsSync(), isFalse, reason: '目录应被清理，不留半缓存');
  });

  test('部分文件下载失败 → 已写文件被清理（半缓存不留）', () async {
    // 前 3 个请求成功，第 4 个失败
    var call = 0;
    final flaky = MockClient((req) async {
      call++;
      if (call == 4) return http.Response('boom', 503);
      return http.Response.bytes(_tinyPng, 200);
    });
    final l = makeLocalizer(client: flaky);

    await expectLater(
      l.download(makeMeta(board: null)),
      throwsA(isA<HttpException>()),
    );
    expect(skinDir().existsSync(), isFalse, reason: '部分成功后失败 → 全清');
  });

  test('棋盘底图扩展名由 contentType 推导（png）', () async {
    final meta = makeMeta(
      board: FileRef(
        fileId: 'c' * 32,
        fileName: 'board.png',
        sizeBytes: 2048,
        contentType: 'image/png',
      ),
    );
    final l = makeLocalizer(client: okClient(), meta: meta);
    await l.download(meta);
    expect(skinFile('boardBackground.png').existsSync(), isTrue);
    expect(skinFile('boardBackground.webp').existsSync(), isFalse);

    final cached = await l.fromCache('t1');
    expect(cached!.boardBackground, isA<FileImage>());
  });

  test('isCached 需 12 棋子齐全 + done 标记（删一张棋子 → false）', () async {
    final l = makeLocalizer(client: okClient());
    await l.download(makeMeta(board: null));
    expect(await l.isCached('t1'), isTrue);

    // 删掉一张棋子 → isCached false
    skinFile('wK.webp').deleteSync();
    expect(await l.isCached('t1'), isFalse, reason: '缺棋子不得命中缓存');

    // 补回棋子但删 done → isCached false
    skinFile('wK.webp').writeAsBytesSync(_tinyPng);
    skinFile('.done').deleteSync();
    expect(await l.isCached('t1'), isFalse, reason: '缺 done 哨兵不得命中缓存');
  });
}
