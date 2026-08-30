// test/lab/demos/chess_online_demo_test.dart
//
// ChessOnlinePage（国际象棋联机入口）皮肤本地化 widget 测试。
//
// 核心契约（修复"皮肤已下载到本地仍 loading 转圈"）：
//   · 磁盘已有完整缓存（12 webp + .done）但内存 _localSkins 未命中时，
//     点选该皮肤 → 走缓存优先路径 → **零网络请求 + 不显示 loading 转圈**。
//   · 未缓存皮肤点选 → 正常触发下载（网络请求 + 下载中转圈）。
//
// 注入：真实 ChessSkinLocalizer（MockClient 计数 + 临时目录 + metaById 查 live
// ChessSkinBundle.metas），SharedPreferences mock 空值（skinId 默认 '1'）。
// 不真正连 relay（不点"进入对局"）；KV 拉取走 fire-and-forget，测试环境静默失败。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_localizer.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_settings_page.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';
import 'package:xiaodouzi_fr/core/theme/colors/factory.dart';
import 'package:xiaodouzi_fr/core/theme/extensions/chess_color_strategy_extension.dart';
import 'package:xiaodouzi_fr/lab/demos/chess_online_demo.dart';

/// 1x1 有效 PNG 字节（写入本地文件 / 模拟下载响应）。
final List<int> _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

class _FakeResolver implements FileResolver {
  @override
  String url(String fileId) => 'http://fake/files/$fileId';
}

/// 计数 MockClient：记录 HTTP 调用次数（网络请求 = 真实下载）。
class _CountingClient extends MockClient {
  _CountingClient() : super(_handler);

  /// 计数用 handler：每来一个请求就 +1 并返回 200。
  static Future<http.Response> _handler(http.Request req) async {
    calls++;
    return http.Response.bytes(_tinyPng, 200);
  }

  static int calls = 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late _CountingClient client;
  late ChessSkinLocalizer localizer;

  setUp(() async {
    ChessSkinBundle.resetForTest();
    ChessSkinBundle.registerHardcoded();
    SharedPreferences.setMockInitialValues({});
    _CountingClient.calls = 0;
    tempRoot = await Directory.systemTemp.createTemp('chess_online_demo_');
    // 静态判存根目录指向 tempRoot —— 避免 download() 里 ensureBaseDirInit
    // 依赖 path_provider plugin（widget 测试无 plugin mock 会挂起）。
    ChessSkinLocalizer.setBaseDirForTest(tempRoot);
    client = _CountingClient();
    localizer = ChessSkinLocalizer(
      resolver: _FakeResolver(),
      client: client,
      dirProvider: () async => tempRoot,
      // 与 demo 生产一致：metaById 查 live ChessSkinBundle.metas。
      metaById: (id) {
        for (final m in ChessSkinBundle.metas) {
          if (m.id == id) return m;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    // 下载可能仍在写文件 → 异步删除 + 容忍占用（等 OS 释放）。
    try {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    } catch (_) {
      // 文件被占用（下载残留 handle）→ 忽略，temp 目录由 OS 清理。
    }
    ChessSkinLocalizer.setBaseDirForTest(null);
  });

  /// 把 [id] 皮肤的完整缓存写到磁盘（模拟"以前下载过"）。
  void seedCache(String id) {
    final dir = Directory('${tempRoot.path}/chess_skins/$id')
      ..createSync(recursive: true);
    for (final key in kChessSkin12PieceKeys) {
      File('${dir.path}/$key.webp').writeAsBytesSync(_tinyPng);
    }
    File(
      '${dir.path}/${ChessSkinLocalizer.kDoneMarker}',
    ).writeAsStringSync('ok\n');
  }

  /// 带 ChessColorStrategyExtension 的宿主（页面读 context.chessColors 需要）。
  Widget host() {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(),
        extensions: [
          ChessColorStrategyExtension(
            ThemeStrategyFactory.createChessColorStrategy(
              const ColorScheme.light(),
            ),
          ),
        ],
      ),
      home: ChessOnlinePage(localizer: localizer),
    );
  }

  testWidgets('磁盘已缓存但内存未命中 → 点皮肤零网络 + 不转圈', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 前置：磁盘已有 '1'（prefs 默认预取）和 '2' 的完整缓存。
    // initState 预取 '1' 命中缓存（零网络）；点 '2' 时 _localSkins 未命中
    // 但磁盘已缓存 → 应零网络加载，不转圈。
    seedCache('1');
    seedCache('2');
    expect(await localizer.isCached('2'), isTrue, reason: '前置：磁盘缓存就绪');

    await tester.pumpWidget(host());
    // 让 initState 异步（prefs read / KV fetch / 缓存加载）settle。
    // 用有界 pump 而非 pumpAndSettle（转圈动画会导致 pumpAndSettle 永不结束）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // 记录点击前的网络请求数（排除 initState 期间可能的请求）。
    final callsBefore = _CountingClient.calls;

    // 打开换肤设置页（调色盘按钮）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 页面过渡动画

    // 点击皮肤 '2'（磁盘已缓存，内存 Map 未命中）。
    final skin2 = ChessSkinBundle.metas.firstWhere((m) => m.id == '2');
    await tester.tap(find.widgetWithText(ListTile, skin2.displayName).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 核心断言：零网络请求 + 预览不转圈。
    expect(_CountingClient.calls, callsBefore, reason: '已缓存皮肤点选不得触发网络下载');
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '已缓存皮肤不得显示 loading 转圈',
    );
  });

  testWidgets('未缓存皮肤 → 点选触发网络下载 + 转圈', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 前置：磁盘无任何缓存（'1' 也无）→ initState 预取 '1' 会下载。
    // 为隔离"点皮肤下载"场景，预置 '1' 缓存让 initState 零网络，
    // 只测点 '2'（未缓存）时的下载行为。
    seedCache('1');
    expect(await localizer.isCached('2'), isFalse, reason: '前置：皮肤 2 无缓存');

    await tester.pumpWidget(host());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // 页面过渡动画
    // 确认设置页已打开。
    expect(find.byType(ChessSkinSettingsPage), findsOneWidget,
        reason: '调色盘按钮应打开换肤设置页');

    final callsBefore = _CountingClient.calls;

    final skin2 = ChessSkinBundle.metas.firstWhere((m) => m.id == '2');
    await tester.runAsync(() async {
      // 下载是真实文件 IO —— 必须在 runAsync 里完成（fake async 不推进真实 IO）。
      await tester.tap(find.widgetWithText(ListTile, skin2.displayName).first);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 下载中应触发网络请求。
    expect(_CountingClient.calls, greaterThan(callsBefore), reason: '未缓存皮肤应触发下载');
    // 下载完成后转圈消失（MockClient 立即返回）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: '下载完成后转圈消失',
    );
  });
}
