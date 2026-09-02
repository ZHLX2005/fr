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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart'
    show
        FileImage,
        ImageConfiguration,
        ImageStreamCompleter,
        ImageStreamListener,
        PaintingBinding;
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

      // 目录内容：12 张棋子 + boardBackground.webp + .done + .skin-meta.json = 15 个文件
      final files = skinDir().listSync().toList();
      expect(files, hasLength(15),
          reason: '12 棋子 + 棋盘底图 + done 哨兵 + 缓存版本索引（Fix C）');
      expect(skinFile('.done').existsSync(), isTrue);
      expect(skinFile('.skin-meta.json').existsSync(), isTrue,
          reason: 'Fix C：下载成功必须写入缓存版本索引');

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
    'Fix C: download 成功后 .skin-meta.json 含 pieceKey → fileId 映射 + version + boardBackground',
    () async {
      final meta = makeMeta(
        board: FileRef(
          fileId: 'b' * 32,
          fileName: 'board.webp',
          sizeBytes: 2048,
          contentType: 'image/webp',
        ),
      );
      final l = makeLocalizer(client: okClient(), meta: meta);
      await l.download(meta);

      // 读 .skin-meta.json 验证内容
      final raw = jsonDecode(skinFile('.skin-meta.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final entry in meta.pieces.entries) {
        expect(raw[entry.key], entry.value.fileId,
            reason: '${entry.key} 应记录当前 fileId');
      }
      expect(raw['boardBackground'], meta.boardBackground!.fileId,
          reason: '棋盘底图 fileId 应被记录');
      expect(raw['version'], meta.version.toString(),
          reason: 'meta.version 应被记录（便于未来按版本 GC 旧缓存）');
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

  // ─────────────── ensureLocal：缓存优先确保本地化（Fix：磁盘已有缓存不重下） ───────────────

  test('ensureLocal 已缓存 → 直接 fromCache，不触发任何网络请求', () async {
    var httpCalls = 0;
    final counting = MockClient((req) async {
      httpCalls++;
      return http.Response.bytes(_tinyPng, 200);
    });
    final l = makeLocalizer(client: counting);
    // 先真实下载一份到本地（产生缓存）
    await l.download(makeMeta(board: null));
    expect(await l.isCached('t1'), isTrue, reason: '前置：缓存就绪');
    expect(httpCalls, greaterThan(0), reason: '前置：下载确实走过网络');

    // ensureLocal → 命中缓存，绝不再打网络
    httpCalls = 0;
    final skin = await l.ensureLocal(makeMeta(board: null));
    expect(skin, isA<LocalChessSkin>());
    expect(skin.id, 't1');
    expect(httpCalls, 0, reason: '已缓存 → ensureLocal 必须零网络请求');
  });

  test('ensureLocal 未缓存 → 走 download（网络下载）', () async {
    final l = makeLocalizer(client: okClient());
    expect(await l.isCached('t1'), isFalse, reason: '前置：无缓存');

    final skin = await l.ensureLocal(makeMeta(board: null));
    expect(skin, isA<LocalChessSkin>());
    expect(await l.isCached('t1'), isTrue, reason: 'ensureLocal 后应产生缓存');
  });

  test('ensureLocal 已缓存但 fromCache 构造失败 → 走 download（兜底重下）', () async {
    // 缓存目录只有 done 标记但棋子文件被删 → isCached false → 走 download
    final l = makeLocalizer(client: okClient());
    await l.download(makeMeta(board: null));
    expect(await l.isCached('t1'), isTrue);

    // 删掉全部棋子文件 → isCached 变 false（目录仍在）
    for (final k in kChessSkin12PieceKeys) {
      skinFile('$k.webp').deleteSync();
    }
    expect(await l.isCached('t1'), isFalse, reason: '棋子缺失 → 缓存不完整');

    final skin = await l.ensureLocal(makeMeta(board: null));
    expect(skin, isA<LocalChessSkin>());
    expect(await l.isCached('t1'), isTrue, reason: 'ensureLocal 重新补齐缓存');
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
    expect(files, hasLength(14),
        reason: '12 棋子 + done + .skin-meta.json（Fix C，无棋盘底图）');
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

  group('ChessSkinLocalizer.cachedPieceFile（Fix B + Fix C）', () {
    late Directory cacheRoot;

    /// 当前测试用 fileId（与 makeMeta 生成规则同步）。
    String fId() => 'wK_fid'.padRight(32, 'a');

    /// 把 `.skin-meta.json` 写入测试皮肤目录（Fix C 校验需要）。
    /// 测试不需要包含全部 12 pieceKey；缺哪个视为不匹配（命中规则严格）。
    void writeSkinMeta(String skinId, {Map<String, String>? pieces, bool include = true}) {
      if (!include) return;
      final dir = Directory('${cacheRoot.path}/chess_skins/$skinId');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final idx = <String, String>{
        'wK': pieces?['wK'] ?? 'wK_fid'.padRight(32, 'a'),
        'wQ': pieces?['wQ'] ?? 'wQ_fid'.padRight(32, 'a'),
      };
      File('${dir.path}/.skin-meta.json').writeAsStringSync(jsonEncode(idx));
    }

    setUp(() {
      cacheRoot = Directory.systemTemp.createTempSync('chess_skin_cache_root_');
      addTearDown(() {
        if (cacheRoot.existsSync()) cacheRoot.deleteSync(recursive: true);
        // 复位静态根目录 + 清 memo，避免污染其它测试。
        ChessSkinLocalizer.setBaseDirForTest(null);
      });
    });

    test('根目录注入后：已有文件 + fileId 匹配 → 返回 File', () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final skinDir =
          Directory('${cacheRoot.path}/chess_skins/t1')..createSync(recursive: true);
      File('${skinDir.path}/wK.webp').writeAsBytesSync(_tinyPng);
      writeSkinMeta('t1', pieces: {'wK': 'wK_fid'.padRight(32, 'a')});

      final hit = ChessSkinLocalizer.cachedPieceFile(
        't1', 'wK.webp',
        expectedFileId: 'wK_fid'.padRight(32, 'a'),
      );
      expect(hit, isNotNull, reason: '已落盘 + fileId 匹配 → 应命中');
      expect(hit!.existsSync(), isTrue);
      expect(
        hit.path.replaceAll('\\', '/'),
        endsWith('chess_skins/t1/wK.webp'),
      );

      expect(
        ChessSkinLocalizer.cachedPieceFile(
          't1', 'wQ.webp',
          expectedFileId: 'wQ_fid'.padRight(32, 'a'),
        ),
        isNull,
        reason: '未落盘文件返回 null（回退网络）',
      );
      expect(
        ChessSkinLocalizer.cachedPieceFile(
          'nope', 'wK.webp',
          expectedFileId: 'wK_fid'.padRight(32, 'a'),
        ),
        isNull,
        reason: '未知皮肤目录返回 null',
      );
    });

    // ─────────────── Fix C：缓存版本校验（核心 bug 修复） ───────────────

    test(
      'Fix C: 文件存在但 expectedFileId 与 .skin-meta.json 不匹配 → 返回 null',
      () {
        // 重现「换图不更新」bug：本地目录里有 wK.webp（旧图），
        // .skin-meta.json 记录的是旧 fileId，但 current meta 期望新 fileId。
        // 旧版 cachedPieceFile 会返回旧 File（导致 RemoteChessSkin 用旧图）；
        // 新版必须返回 null → RemoteChessSkin 走网络拉新图。
        ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
        final skinDir = Directory('${cacheRoot.path}/chess_skins/t1')
          ..createSync(recursive: true);
        File('${skinDir.path}/wK.webp').writeAsBytesSync(_tinyPng);
        // 索引里写的是旧 fileId
        const oldFid = 'OLD_FILE_ID_OLD_FILE_ID_OLD_FILE_';
        writeSkinMeta('t1', pieces: {'wK': oldFid});

        // 期望新 fileId → 必须返回 null（视为未命中）
        const newFid = 'NEW_FILE_ID_NEW_FILE_ID_NEW_FILE_';
        final hit = ChessSkinLocalizer.cachedPieceFile(
          't1', 'wK.webp',
          expectedFileId: newFid,
        );
        expect(hit, isNull, reason: 'fileId 不一致 → 必须视作未命中');
      },
    );

    test(
      'Fix C: 文件存在但 .skin-meta.json 缺失 → 返回 null（迁移兼容）',
      () {
        // 旧设备首次遇到本修复：目录里只有图片没有索引 → 走网络重下（正确行为）。
        ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
        final skinDir = Directory('${cacheRoot.path}/chess_skins/t1')
          ..createSync(recursive: true);
        File('${skinDir.path}/wK.webp').writeAsBytesSync(_tinyPng);
        // 不写 .skin-meta.json（模拟旧缓存）

        final hit = ChessSkinLocalizer.cachedPieceFile(
          't1', 'wK.webp',
          expectedFileId: 'wK_fid'.padRight(32, 'a'),
        );
        expect(hit, isNull, reason: '索引缺失 → 视作未命中（迁移到新机制）');
      },
    );

    test(
      'Fix C: .skin-meta.json 损坏 → 返回 null（防御）',
      () {
        ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
        final skinDir = Directory('${cacheRoot.path}/chess_skins/t1')
          ..createSync(recursive: true);
        File('${skinDir.path}/wK.webp').writeAsBytesSync(_tinyPng);
        File('${skinDir.path}/.skin-meta.json')
            .writeAsStringSync('not a json {{{');

        final hit = ChessSkinLocalizer.cachedPieceFile(
          't1', 'wK.webp',
          expectedFileId: 'wK_fid'.padRight(32, 'a'),
        );
        expect(hit, isNull, reason: '损坏索引 → 走网络而非崩溃');
      },
    );

    test('根目录未初始化 → 恒 null（行为退化网络）', () {
      // 默认（/ 复位后）未注入根目录
      expect(
        ChessSkinLocalizer.cachedPieceFile(
          't1', 'wK.webp',
          expectedFileId: 'wK_fid'.padRight(32, 'a'),
        ),
        isNull,
      );
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
      expect(
        ChessSkinLocalizer.cachedPieceFile(
          't1', 'wK.webp',
          expectedFileId: 'wK_fid'.padRight(32, 'a'),
        ),
        isNull,
      );

      final meta = makeMeta(board: null);
      await l.download(meta);

      // 下载完成 → 同步判存命中（无需重新 await path_provider）
      final expectedFid = meta.pieces['wK']!.fileId;
      final hit = ChessSkinLocalizer.cachedPieceFile(
        't1', 'wK.webp',
        expectedFileId: expectedFid,
      );
      expect(hit, isNotNull, reason: 'download 后静态判存应立即命中');
      expect(hit!.existsSync(), isTrue);
    });
  });

  // ─────────────── RemoteChessSkin 本地文件优先（Fix B + Fix C） ───────────────

  group('RemoteChessSkin 本地文件优先（Fix B + Fix C）', () {
    late Directory cacheRoot;

    /// 模拟 download 完毕的皮肤目录（含 .skin-meta.json）。
    /// fileId 默认用 makeMeta 的生成规则，保证匹配。
    void setupCachedSkin(String skinId, {Map<String, String>? overrides}) {
      final dir = Directory('${cacheRoot.path}/chess_skins/$skinId')
        ..createSync(recursive: true);
      final idx = <String, String>{
        for (final k in kChessSkin12PieceKeys)
          k: (overrides?[k]) ?? '${k}_fid'.padRight(32, 'a'),
      };
      File('${dir.path}/.skin-meta.json').writeAsStringSync(jsonEncode(idx));
      // 12 张棋子文件全部落盘（piece key → ${key}.webp）
      for (final k in kChessSkin12PieceKeys) {
        File('${dir.path}/$k.webp').writeAsBytesSync(_tinyPng);
      }
    }

    /// 当前测试用 meta → 拿它 key 实际 fileId 拼成 meta → RemoteChessSkin。
    ChessSkinMeta currentMeta({FileRef? board}) => makeMeta(board: board);

    setUp(() {
      cacheRoot = Directory.systemTemp.createTempSync('chess_skin_remote_');
      addTearDown(() {
        if (cacheRoot.existsSync()) cacheRoot.deleteSync(recursive: true);
        ChessSkinLocalizer.setBaseDirForTest(null);
      });
    });

    test('本地已缓存 + fileId 全匹配 → pieces[key] 是 FileImage（零网络）',
        () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      setupCachedSkin('t1');

      final s = RemoteChessSkin(meta: currentMeta(), fileResolver: _FakeResolver());
      for (final img in s.pieces.values) {
        expect(img, isA<FileImage>(), reason: '缓存命中 → FileImage 渲染');
      }
    });

    test(
      'Fix C: 本地有图但 .skin-meta.json 缺失 → 全部 CachedNetworkImageProvider',
      () {
        // 旧设备首次遇到本修复：本地目录只有图，没有索引 → 走网络重下
        ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
        final dir = Directory('${cacheRoot.path}/chess_skins/t1')
          ..createSync(recursive: true);
        File('${dir.path}/wK.webp').writeAsBytesSync(_tinyPng);
        // 不写 .skin-meta.json

        final s = RemoteChessSkin(meta: currentMeta(), fileResolver: _FakeResolver());
        for (final img in s.pieces.values) {
          expect(img, isA<CachedNetworkImageProvider>(),
              reason: '索引缺失 → 视为未缓存，走网络');
        }
      },
    );

    test(
      'Fix C: 本地有图 + 索引存在但 wK 的 fileId 不一致 → 仅 wK 走网络，其余仍命中',
      () {
        // 端到端验证核心 bug 修复：服务端改了 wK 图（new fileId 发布），
        // KV index 已更新；FR 本地缓存里 wK.webp 是旧图，且 .skin-meta.json 里
        // wK 的 fileId 是旧的。其它 11 张图 fileId 未变 → 仍命中本地。
        ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
        final dir = Directory('${cacheRoot.path}/chess_skins/t1')
          ..createSync(recursive: true);
        // 12 张图全部落盘
        for (final k in kChessSkin12PieceKeys) {
          File('${dir.path}/$k.webp').writeAsBytesSync(_tinyPng);
        }
        // 索引里把 wK 标成 OLD，其余用当前 meta 的 fileId
        final cur = currentMeta();
        final idx = <String, String>{
          for (final k in kChessSkin12PieceKeys)
            k: k == 'wK' ? 'OLD_FILE_ID_OLD_FILE_ID_OLD_FILE_' : cur.pieces[k]!.fileId,
        };
        File('${dir.path}/.skin-meta.json').writeAsStringSync(jsonEncode(idx));

        final s = RemoteChessSkin(meta: cur, fileResolver: _FakeResolver());
        expect(s.pieces['wK'], isA<CachedNetworkImageProvider>(),
            reason: 'wK fileId 不一致 → 走网络拉新图');
        expect(s.pieces['wQ'], isA<FileImage>(),
            reason: 'wQ fileId 一致 → 命中本地缓存');
        expect(s.pieces['bp'], isA<FileImage>(),
            reason: 'bp fileId 一致 → 命中本地缓存');
      },
    );

    test('无本地缓存 → 全部 CachedNetworkImageProvider', () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final s = RemoteChessSkin(meta: currentMeta(), fileResolver: _FakeResolver());
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
      final meta = currentMeta(board: board);
      expect(
        RemoteChessSkin(meta: meta, fileResolver: _FakeResolver()).boardBackground,
        isA<CachedNetworkImageProvider>(),
      );
    });

    test('boardBackground 本地已缓存 + 索引匹配 → FileImage', () {
      ChessSkinLocalizer.setBaseDirForTest(cacheRoot);
      final board = FileRef(
        fileId: 'b' * 32,
        fileName: 'board.webp',
        sizeBytes: 2048,
        contentType: 'image/webp',
      );
      final meta = currentMeta(board: board);
      final dir = Directory('${cacheRoot.path}/chess_skins/t1')
        ..createSync(recursive: true);
      File('${dir.path}/boardBackground.webp').writeAsBytesSync(_tinyPng);
      // 索引里写 boardBackground → fileId 匹配
      File('${dir.path}/.skin-meta.json').writeAsStringSync(jsonEncode({
        for (final k in kChessSkin12PieceKeys) k: meta.pieces[k]!.fileId,
        'boardBackground': board.fileId,
      }));
      expect(
        RemoteChessSkin(meta: meta, fileResolver: _FakeResolver()).boardBackground,
        isA<FileImage>(),
        reason: '底图已落盘 + 索引匹配 → 本地文件渲染',
      );
    });
  });
  // ─────────────── Fix C-2：KV 换图 → 旧缓存自动失效 ───────────────

  test('isCached fileId 版本校验：meta 换 fileId → 旧缓存不命中（触发重下）', () async {
    final oldMeta = makeMeta();
    final l = makeLocalizer(client: okClient(), meta: oldMeta);
    await l.download(oldMeta);
    expect(await l.isCached('t1'), isTrue);

    // KV 换图：同一 skinId 的新 meta，wK 的 fileId 变了
    final newPieces = Map<String, FileRef>.of(oldMeta.pieces);
    newPieces['wK'] = FileRef(
      fileId: 'f' * 32, // 新 fileId
      fileName: 'wK.webp',
      sizeBytes: 200,
      contentType: 'image/webp',
    );
    final newMeta = ChessSkinMeta(
      id: oldMeta.id,
      displayName: oldMeta.displayName,
      pieces: newPieces,
    );
    final l2 = makeLocalizer(client: okClient(), meta: newMeta);
    expect(
      await l2.isCached('t1'),
      isFalse,
      reason: 'KV 换图（fileId 变更）后旧缓存必须失效 → ensureLocal 走 download 重下',
    );

    // 重下（download 用新 meta）→ 新索引写入 → isCached 重新命中
    await l2.download(newMeta);
    expect(await l2.isCached('t1'), isTrue);
  });

  test('isCached fileId 版本校验：.skin-meta.json 缺失/畸形 → false', () async {
    final l = makeLocalizer(client: okClient());
    await l.download(makeMeta());
    expect(await l.isCached('t1'), isTrue);

    // 删索引文件 → 无法校验版本 → false（迁移策略：触发重下）
    skinFile('.skin-meta.json').deleteSync();
    expect(await l.isCached('t1'), isFalse);

    // 畸形索引（非法 JSON）→ false
    skinFile('.skin-meta.json').writeAsStringSync('{not json');
    expect(await l.isCached('t1'), isFalse);
  });

  test('download 后 evict ImageCache：FileImage.obtainKey 同路径 keys 相等（evict 生效前提）', () async {
    final meta = makeMeta();
    final l = makeLocalizer(client: okClient(), meta: meta);
    await l.download(meta);

    // FileImage 的 ImageCache key 按 path 相等 —— 生产的 _evictImageCache
    // 用 FileImage(同 path).evict() 逐出旧缓存的前提是 keys 相等。
    final keyA = await FileImage(skinFile('wK.webp')).obtainKey(ImageConfiguration.empty);
    final keyB = await FileImage(skinFile('wK.webp')).obtainKey(ImageConfiguration.empty);
    expect(keyA, keyB,
        reason: '同路径 FileImage 的 keys 必须相等，否则生产的 _evictImageCache 失效');

    // 验证 download 最新调用后，生产路径的 ImageCache evict 不抛错
    PaintingBinding.instance.imageCache.putIfAbsent(keyA, () => InstantiationStub());
    await l.download(meta);
    expect(
      () async => await FileImage(skinFile('wK.webp')).evict(),
      returnsNormally,
      reason: '重下后 evict 同路径 FileImage 不应抛错',
    );
  });
}

/// ImageCache.putIfAbsent 的最小 loader stub（不真正解码图片）。
class InstantiationStub extends ImageStreamCompleter {
  @override
  void addListener(ImageStreamListener l) {}
  @override
  void removeListener(ImageStreamListener l) {}
}
