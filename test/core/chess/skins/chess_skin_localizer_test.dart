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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_localizer.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';
import 'package:xiaodouzi_fr/core/chess/skins/local_chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/remote_chess_skin.dart';

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

  ChessSkinLocalizer makeLocalizer({
    http.Client? client,
    ChessSkinMeta? meta,
    Duration? timeout,
  }) {
    return ChessSkinLocalizer(
      resolver: _FakeResolver(),
      client: client,
      dirProvider: () async => tempRoot,
      // 测试皮肤 id 't1' 不在 const catalog → 注入自定义 meta 解析。
      // [meta] 传给 isCached/fromCache 用的 meta（默认无 boardBackground）。
      metaById: (id) => id == 't1' ? (meta ?? makeMeta()) : null,
      timeout: timeout,
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

  test('网络黑洞（GET 永不完成）→ 超时抛 TimeoutException + 目录被清理', () async {
    // 真机踩坑：不可达但不立刻拒绝的网络下 http.get 挂死 → loading 永转圈。
    // 防回归：注入短超时，永远不完成的 MockClient 必须在超时内落到失败路径。
    final neverCompletes = MockClient(
      (req) => Completer<http.Response>().future,
    );
    final l = makeLocalizer(client: neverCompletes, timeout: const Duration(milliseconds: 50));

    await expectLater(
      l.download(makeMeta(board: null)),
      throwsA(isA<TimeoutException>()),
    );
    expect(await l.isCached('t1'), isFalse, reason: '超时后不得命中缓存');
    expect(skinDir().existsSync(), isFalse, reason: '超时后目录应被清理');
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

  // ─────────────── 静态同步判存（Fix B：本地文件优先渲染） ───────────────

  group('ChessSkinLocalizer.cachedPieceFile（Fix B）', () {
    late Directory cacheRoot;

    setUp(() {
      cacheRoot = Directory.systemTemp.createTempSync('chess_skin_cache_root_');
      addTearDown(() {
        if (cacheRoot.existsSync()) cacheRoot.deleteSync(recursive: true);
        // 复位静态根目录 + 清 memo，避免污染其它测试。
        ChessSkinLocalizer.setBaseDirForTest(null);
      });
    });

    test('根目录注入后：已有文件返回 File，缺失返回 null', () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final skinDir =
          Directory('${cacheRoot.path}/chess_skins/t1')..createSync(recursive: true);
      File('${skinDir.path}/wK.webp').writeAsBytesSync(_tinyPng);

      final hit = ChessSkinLocalizer.cachedPieceFile('t1', 'wK.webp');
      expect(hit, isNotNull, reason: '已落盘文件应判存命中');
      // 路径分隔符不跨平台断言：只验证"同一文件 + 落在目标目录"。
      expect(hit!.existsSync(), isTrue);
      expect(
        hit.path.replaceAll('\\', '/'),
        endsWith('chess_skins/t1/wK.webp'),
      );

      expect(
        ChessSkinLocalizer.cachedPieceFile('t1', 'wQ.webp'),
        isNull,
        reason: '未落盘文件返回 null（回退网络）',
      );
      expect(
        ChessSkinLocalizer.cachedPieceFile('nope', 'wK.webp'),
        isNull,
        reason: '未知皮肤目录返回 null',
      );
    });

    test('根目录未初始化 → 恒 null（行为退化网络）', () {
      // 默认（/ 复位后）未注入根目录
      expect(ChessSkinLocalizer.cachedPieceFile('t1', 'wK.webp'), isNull);
    });

    test('download 落盘后静态判存立即可见（memo 失效生效）', () async {
      // 静态根目录与 localizer 写入目录必须同源（都是 cacheRoot），
      // download 结束后 cachedPieceFile 才能立刻命中。
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final l = ChessSkinLocalizer(
        resolver: _FakeResolver(),
        client: okClient(),
        dirProvider: () async => cacheRoot,
        metaById: (id) => id == 't1' ? makeMeta() : null,
      );

      // 下载前判存 miss
      expect(ChessSkinLocalizer.cachedPieceFile('t1', 'wK.webp'), isNull);

      await l.download(makeMeta(board: null));

      // 下载完成 → 同步判存命中（无需重新 await path_provider）
      final hit = ChessSkinLocalizer.cachedPieceFile('t1', 'wK.webp');
      expect(hit, isNotNull, reason: 'download 后静态判存应立即命中');
      expect(hit!.existsSync(), isTrue);
    });
  });

  // ─────────────── RemoteChessSkin 本地文件优先（Fix B） ───────────────

  group('RemoteChessSkin 本地文件优先（Fix B）', () {
    late Directory cacheRoot;

    setUp(() {
      cacheRoot = Directory.systemTemp.createTempSync('chess_skin_remote_');
      addTearDown(() {
        if (cacheRoot.existsSync()) cacheRoot.deleteSync(recursive: true);
        ChessSkinLocalizer.setBaseDirForTest(null);
      });
    });

    test('本地已缓存 → pieces[key] 是 FileImage（零网络）', () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final skinDir =
          Directory('${cacheRoot.path}/chess_skins/t1')..createSync(recursive: true);
      File('${skinDir.path}/wK.webp').writeAsBytesSync(_tinyPng);

      final s = RemoteChessSkin(meta: makeMeta(), fileResolver: _FakeResolver());
      final img = s.pieces['wK']!;
      expect(img, isA<FileImage>(), reason: '本地文件存在 → FileImage 渲染');
      // 未缓存 key 仍走网络
      expect(s.pieces['wQ'], isA<CachedNetworkImageProvider>());
    });

    test('无本地缓存 → 全部 CachedNetworkImageProvider', () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final s = RemoteChessSkin(meta: makeMeta(), fileResolver: _FakeResolver());
      for (final img in s.pieces.values) {
        expect(img, isA<CachedNetworkImageProvider>(), reason: '未缓存 → 网络');
      }
      expect(s.boardBackground, isNull, reason: 'meta 无底图 → null');
    });

    test('boardBackground 未缓存 → 网络', () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final board = FileRef(
        fileId: 'b' * 32,
        fileName: 'board.webp',
        sizeBytes: 2048,
        contentType: 'image/webp',
      );
      final meta = makeMeta(board: board);
      expect(
        RemoteChessSkin(meta: meta, fileResolver: _FakeResolver()).boardBackground,
        isA<CachedNetworkImageProvider>(),
      );
    });

    test('boardBackground 本地已缓存 → FileImage', () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final board = FileRef(
        fileId: 'b' * 32,
        fileName: 'board.webp',
        sizeBytes: 2048,
        contentType: 'image/webp',
      );
      final meta = makeMeta(board: board);
      // 先落盘 boardBackground.webp，再判存（无先前 miss 污染 memo）
      final skinDir =
          Directory('${cacheRoot.path}/chess_skins/t1')..createSync(recursive: true);
      File('${skinDir.path}/boardBackground.webp').writeAsBytesSync(_tinyPng);
      expect(
        RemoteChessSkin(meta: meta, fileResolver: _FakeResolver()).boardBackground,
        isA<FileImage>(),
        reason: '底图已落盘 → 本地文件渲染',
      );
    });
  });
}
