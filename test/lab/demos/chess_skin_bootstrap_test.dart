// test/lab/demos/chess_skin_bootstrap_test.dart
//
// ChessOnlinePage 皮肤线上化（id49）首启流程 widget 测试：
//   · 首启无缓存 + KV 强拉失败 → 页面横幅"皮肤资源初始化失败" + 重试按钮
//   · 强拉成功 → 无横幅；prefs 缺省 → 选中线上第一套并预取下载
//   · 磁盘有持久化 index → 离线恢复（不走网络强拉）
//   · prefs 持久化 id 已失效（线上下架）→ 回退线上第一套

import 'dart:convert';
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
import 'package:xiaodouzi_fr/core/game_kit/skin/game_skin_bundle.dart';
import 'package:xiaodouzi_fr/core/theme/colors/factory.dart';
import 'package:xiaodouzi_fr/core/theme/extensions/chess_color_strategy_extension.dart';
import 'package:xiaodouzi_fr/lab/demos/chess_online_demo.dart';

/// 1x1 有效 PNG 字节（模拟下载响应体）。
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

/// 图片下载用的 MockClient（返回 1x1 PNG；下载链路在 FakeAsync 中不依赖其完成）。
MockClient _imageClient() =>
    MockClient((req) async => http.Response.bytes(_tinyPng, 200));

/// 生成一套完整 12-piece 的皮肤 meta JSON（保证 LocalGameSkin.tryCreate 成功）。
String _metaJson(String id, {String? displayName}) {
  final pieces = {
    for (final key in kChessSkin12PieceKeys)
      key: {
        'fileId': 'fid-$id-$key',
        'fileName': '$key.webp',
        'sizeBytes': 8,
        'contentType': 'image/webp',
      },
  };
  return jsonEncode({
    'id': id,
    'displayName': displayName ?? '皮肤$id',
    'version': 1,
    'pieces': pieces,
  });
}

/// 把 index 持久化文件写入测试 base 目录（模拟上次启动成功拉取后落盘）。
void _seedPersistedIndex(Directory tempRoot, String rawJson) {
  final dir = Directory('${tempRoot.path}/chess_skins')
    ..createSync(recursive: true);
  File('${dir.path}/${GameSkinBundle.kIndexCacheFileName}')
      .writeAsStringSync(jsonEncode({'baseUrl': 'http://host', 'index': rawJson}));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late ChessSkinLocalizer localizer;

  setUp(() async {
    // 注意：不调 registerHardcoded —— 生产已删除启动期注册，注册表初始为空。
    ChessSkinBundle.resetForTest();
    SharedPreferences.setMockInitialValues({});
    tempRoot = await Directory.systemTemp.createTemp('chess_bootstrap_');
    ChessSkinLocalizer.setBaseDirForTest(tempRoot);
    localizer = ChessSkinLocalizer(
      resolver: _FakeResolver(),
      client: _imageClient(),
      dirProvider: () async => tempRoot,
      metaById: (id) {
        for (final m in ChessSkinBundle.metas) {
          if (m.id == id) return m;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    try {
      if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
    } catch (_) {}
    ChessSkinLocalizer.setBaseDirForTest(null);
  });

  Widget host({Future<bool> Function()? onFetch}) {
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
      home: ChessOnlinePage(localizer: localizer, onFetchKvIndex: onFetch),
    );
  }

  testWidgets('首启无缓存 + KV 强拉失败 → 横幅提示 + 重试按钮', (tester) async {
    await tester.pumpWidget(host(onFetch: () async => false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('皮肤资源初始化失败'), findsOneWidget,
        reason: '首启强拉失败必须有可见的错误横幅');
    expect(find.text('重试'), findsOneWidget, reason: '横幅必须提供重试入口');
  });

  testWidgets('强拉失败后点重试 → 成功则横幅消失且选中线上第一套', (tester) async {
    var fail = true;
    Future<bool> fetch() async {
      if (fail) return false;
      ChessSkinBundle.bundle.registerRemoteSkins(
        GameSkinMeta.parseList('[${_metaJson('s1')}]'),
        fileResolver: const PublicFileResolver(baseUrl: 'http://host'),
      );
      return true;
    }

    await tester.pumpWidget(host(onFetch: fetch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('皮肤资源初始化失败'), findsOneWidget);

    // 恢复网络后重试。
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('皮肤资源初始化失败'), findsNothing,
        reason: '重试成功后横幅应消失');
  });

  testWidgets('强拉成功 + prefs 缺省 → 选中线上第一套并进入下载中', (tester) async {
    await tester.pumpWidget(
      host(
        onFetch: () async {
          ChessSkinBundle.bundle.registerRemoteSkins(
            GameSkinMeta.parseList(
              '[${_metaJson('s1')},${_metaJson('s2')}]',
            ),
            fileResolver: const PublicFileResolver(baseUrl: 'http://host'),
          );
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('皮肤资源初始化失败'), findsNothing);

    // 换肤设置页列表以线上清单为准（含 s1 / s2），且 s1 为选中态
    // （prefs 缺省 → 回退线上第一套）。下载走真实文件 IO（FakeAsync 中
    // 不会完成）→ 预览区停在"下载中" spinner，即预取已触发的证据。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ChessSkinSettingsPage), findsOneWidget);
    expect(find.text('皮肤s1'), findsWidgets);
    expect(find.text('皮肤s2'), findsOneWidget);
    final selectedTile = find.widgetWithIcon(ListTile, Icons.check_circle);
    expect(selectedTile, findsOneWidget, reason: '线上第一套 s1 应为选中态');
    expect(
      find.descendant(
        of: selectedTile,
        matching: find.text('皮肤s1'),
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget,
        reason: '选中皮肤未缓存 → 预览区应显示下载中 spinner');
  });

  testWidgets('磁盘有持久化 index → 离线恢复，不走网络强拉', (tester) async {
    _seedPersistedIndex(
      tempRoot,
      '[${_metaJson('r1')},${_metaJson('r2')}]',
    );
    var fetchCalled = false;
    await tester.pumpWidget(
      host(
        onFetch: () async {
          fetchCalled = true;
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(fetchCalled, isFalse, reason: '恢复成功后不应再强拉 KV');
    expect(find.textContaining('皮肤资源初始化失败'), findsNothing);

    // 注册表已恢复 → 设置页可见线上两套（选中 tile 标题与预览区 displayName
    // 都会出现"皮肤r1"，故用 findsWidgets）。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('皮肤r1'), findsWidgets);
    expect(find.text('皮肤r2'), findsOneWidget);
  });

  testWidgets('prefs 持久化 id 已失效 → 回退线上第一套', (tester) async {
    SharedPreferences.setMockInitialValues({'chess_skin_id': 'gone-id'});
    await tester.pumpWidget(
      host(
        onFetch: () async {
          ChessSkinBundle.bundle.registerRemoteSkins(
            GameSkinMeta.parseList('[${_metaJson('s1')}]'),
            fileResolver: const PublicFileResolver(baseUrl: 'http://host'),
          );
          return true;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('皮肤资源初始化失败'), findsNothing);

    // _skinId 回退 s1 → 打开设置页验证选中态落在 s1 上；下载走真实文件 IO
    // （FakeAsync 中不会完成）→ spinner 常亮即预取已触发。
    await tester.tap(find.byIcon(Icons.palette_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final selectedTile = find.widgetWithIcon(ListTile, Icons.check_circle);
    expect(selectedTile, findsOneWidget, reason: '回退后线上第一套 s1 应为选中态');
    expect(
      find.descendant(
        of: selectedTile,
        matching: find.text('皮肤s1'),
      ),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
