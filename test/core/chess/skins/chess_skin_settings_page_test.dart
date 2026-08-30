// test/core/chess/skins/chess_skin_settings_page_test.dart
//
// 全屏换肤设置页（ChessSkinSettingsPage）widget 测试：
//   · AppBar 返回箭头存在
//   · 左侧皮肤列表渲染 7 套（displayName 全部可见）
//   · 点击皮肤 → 预览区 ChessBoard 更新（真实渲染，非占位）
//   · 宽屏两栏 / 窄屏竖排布局都存在
//   · 返回（BackButton + 系统 back）→ pop 携带当前选中皮肤 id
//
// 本地皮肤预览（skin localizer 接入后新增）：
//   · 传 localSkins → 预览用本地皮肤（FileImage 本地文件）渲染
//   · 点击未本地化皮肤 → onRequestDownload 回调触发
//   · isDownloading == true → 预览区显示 loading（CircularProgressIndicator）
//   · 未本地化且未下载 → 回退注册表（RemoteChessSkin）
//
// 注：页面不直接读写 SharedPreferences（持久化在调用方），
// 故测试不 mock prefs；但注册表需要 registerHardcoded 才能按 id 解析皮肤。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_settings_page.dart';
import 'package:xiaodouzi_fr/core/chess/skins/file_resolver.dart';
import 'package:xiaodouzi_fr/core/chess/skins/local_chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/board_palette.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/theme/colors/factory.dart';
import 'package:xiaodouzi_fr/core/theme/extensions/chess_color_strategy_extension.dart';

void main() {
  setUp(() {
    ChessSkinBundle.resetForTest();
    ChessSkinBundle.registerHardcoded();
  });

  /// 构造一个最小完整 12-key 的 KV meta（Fix A：KV 合入的新皮肤）。
  ChessSkinMeta kvMeta(String id, {String displayName = 'KV皮肤'}) =>
      ChessSkinMeta(
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

  /// 宿主：注入 ChessColorStrategyExtension，页面才能读 context.chessColors。
  Widget host({
    required String initialSkinId,
    Map<String, LocalChessSkin> localSkins = const {},
    void Function(String)? onRequestDownload,
    bool Function(String)? isDownloading,
    String? Function(String)? downloadError,
    void Function(String)? onRetryDownload,
    BoardPalette? initialPalette,
    void Function(BoardPalette?)? onPaletteChanged,
    Size surfaceSize = const Size(900, 700),
  }) {
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
      home: Builder(
        builder: (context) => ChessSkinSettingsPage(
          initialSkinId: initialSkinId,
          localSkins: localSkins,
          onRequestDownload: onRequestDownload,
          isDownloading: isDownloading,
          downloadError: downloadError,
          onRetryDownload: onRetryDownload,
          initialPalette: initialPalette,
          onPaletteChanged: onPaletteChanged,
        ),
      ),
    );
  }

  group('ChessSkinSettingsPage 布局', () {
    testWidgets('AppBar 标题 + 返回箭头存在', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      expect(find.text('棋盘皮肤'), findsOneWidget);
      expect(
        find.byType(BackButton),
        findsOneWidget,
        reason: '返回箭头是 BackButton 类型',
      );
    });

    testWidgets('宽屏（900px）→ 两栏 Row + 皮肤列表 7 项 + 预览棋盘', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      // 7 套皮肤的 displayName 全部渲染
      // 注：选中皮肤会在"列表项 + 预览标题"出现 2 次，故用 findsWidgets。
      for (final meta in kChessSkinsCatalog) {
        expect(
          find.text(meta.displayName),
          findsWidgets,
          reason: '皮肤 "${meta.displayName}" 应出现在列表中',
        );
      }
      // 实时棋盘预览（真实 ChessBoard）
      expect(find.byType(ChessBoard), findsOneWidget);
      // 选中皮肤（initialSkinId '1'）的勾
      expect(find.byIcon(Icons.check_circle), findsWidgets);
    });

    testWidgets('窄屏（400px）→ 竖排（横向皮肤条 + 下方预览）', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      // 窄屏仍能看到 7 套皮肤（横向滚动条，滚动方向 horizontal）
      final strip = find.byType(ListView);
      expect(strip, findsWidgets);
      // 预览棋盘仍在
      expect(find.byType(ChessBoard), findsOneWidget);
    });
  });

  // ─────────────── Fix A：KV 合入的新皮肤实时可见 ───────────────

  group('ChessSkinSettingsPage KV 皮肤（Fix A）', () {
    testWidgets('注册 KV 新皮肤 → 宽屏列表显示 8 项（含 KV displayName）', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 模拟 KV 合入新皮肤（第 8 套，'pipeline-test'）
      ChessSkinBundle.registerRemoteSkins(
        [kvMeta('pipeline-test', displayName: '流水线测试皮')],
        fileResolver: const PublicFileResolver(baseUrl: 'http://kv-fake'),
      );
      expect(ChessSkinBundle.metaCount, 8);

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      // KV 皮肤的 displayName 出现在列表中
      expect(
        find.text('流水线测试皮'),
        findsWidgets,
        reason: 'Fix A：KV 合入的皮肤必须在设置页列表可见',
      );
      // 7 套本地皮肤仍在
      for (final meta in kChessSkinsCatalog) {
        expect(find.text(meta.displayName), findsWidgets);
      }
    });

    testWidgets('注册 KV 新皮肤 → 窄屏横向条也能渲染 KV 皮肤', (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      ChessSkinBundle.registerRemoteSkins(
        [kvMeta('pipeline-test', displayName: '流水线测试皮')],
        fileResolver: const PublicFileResolver(baseUrl: 'http://kv-fake'),
      );

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      expect(find.byType(ListView), findsWidgets);
      expect(find.byType(ChessBoard), findsOneWidget);
    });

    testWidgets('KV 覆盖同 id → 列表 displayName 显示 KV 版本', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // KV 覆盖本地 '1'（displayName → 'KV-覆盖版'）
      ChessSkinBundle.registerRemoteSkins(
        [kvMeta('1', displayName: 'KV-覆盖版')],
        fileResolver: const PublicFileResolver(baseUrl: 'http://kv-fake'),
      );

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      expect(
        find.text('KV-覆盖版'),
        findsWidgets,
        reason: '同 id 覆盖后列表显示 KV 版本',
      );
    });
  });

  group('ChessSkinSettingsPage 交互', () {
    testWidgets('点击皮肤 → 预览跟随切换 + 勾移动到新皮肤', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      // 初始：皮肤 1 选中
      expect(find.byIcon(Icons.check_circle), findsWidgets);
      // 点击皮肤 2 的名称
      final skin2 = kChessSkinsCatalog[1];
      await tester.tap(find.text(skin2.displayName));
      await tester.pump();

      // 预览名标签切换到皮肤 2（预览区显示 skin.displayName）
      expect(
        find.text(skin2.displayName),
        findsNWidgets(2),
        reason: '列表一项 + 预览标题一项 = 2 处显示皮肤 2 名称',
      );
    });

    testWidgets('BackButton 返回 → pop 携带当前选中皮肤 id', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? popped;
      await tester.pumpWidget(
        MaterialApp(
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const ChessSkinSettingsPage(initialSkinId: '1'),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      // 打开设置页
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ChessSkinSettingsPage), findsOneWidget);

      // 先切换到皮肤 3
      final skin3 = kChessSkinsCatalog[2];
      await tester.tap(find.text(skin3.displayName));
      await tester.pump();

      // 点返回箭头 → pop 携带 skin3.id
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ChessSkinSettingsPage), findsNothing);
      expect(popped, skin3.id, reason: '返回箭头应携带当前选中（已切到皮肤 3）的 id');
    });

    testWidgets('系统返回（页面栈 pop）→ 同样携带当前选中皮肤 id', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? popped;
      await tester.pumpWidget(
        MaterialApp(
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
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) =>
                            const ChessSkinSettingsPage(initialSkinId: '1'),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ChessSkinSettingsPage), findsOneWidget);

      // 切到皮肤 4，然后模拟系统返回
      final skin4 = kChessSkinsCatalog[3];
      await tester.tap(find.text(skin4.displayName));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ChessSkinSettingsPage), findsNothing);
      expect(popped, skin4.id, reason: '系统返回经 PopScope 拦截后也应携带当前选中皮肤 id');
    });
  });

  group('ChessSkinSettingsPage 本地皮肤预览', () {
    /// 构造一个本地皮肤：写 12 张 PNG 到临时目录 + LocalChessSkin。
    LocalChessSkin makeLocalSkin(String id) {
      final dir = Directory.systemTemp.createTempSync('chess_skin_local_$id');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final meta = ChessSkinMeta(
        id: id,
        displayName: '本地皮肤 $id',
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
      for (final k in kChessSkin12PieceKeys) {
        File('${dir.path}/$k.webp').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);
      }
      return LocalChessSkin.tryCreate(meta: meta, dir: dir)!;
    }

    testWidgets('传 localSkins → 预览用本地皮肤（LocalChessSkin）渲染', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final local1 = makeLocalSkin('1');
      await tester.pumpWidget(
        host(initialSkinId: '1', localSkins: {'1': local1}),
      );
      await tester.pump();

      // 预览区显示本地皮肤名（displayName '本地皮肤 1'，出现在预览标题 1 处；
      // 列表项仍显示 catalog 的 displayName）
      expect(find.text('本地皮肤 1'), findsOneWidget);
      // ChessBoard 存在（预览仍真实渲染）
      expect(find.byType(ChessBoard), findsOneWidget);
    });

    testWidgets('点击未本地化皮肤 → onRequestDownload 触发', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final local1 = makeLocalSkin('1');
      final requested = <String>[];
      await tester.pumpWidget(
        host(
          initialSkinId: '1',
          localSkins: {'1': local1},
          onRequestDownload: (id) => requested.add(id),
        ),
      );
      await tester.pump();

      // 点击皮肤 2（未本地化）→ 触发下载回调
      final skin2 = kChessSkinsCatalog[1];
      await tester.tap(find.text(skin2.displayName));
      await tester.pump();

      expect(requested, ['2'], reason: '未本地化皮肤点击应通知调用方下载');
    });

    testWidgets('isDownloading → 预览区显示 loading（CircularProgressIndicator）', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(initialSkinId: '1', isDownloading: (id) => id == '1'),
      );
      await tester.pump();

      // 预览区 loading 代替 ChessBoard
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byType(ChessBoard),
        findsNothing,
        reason: '下载中不渲染棋盘，显示 loading',
      );
      expect(find.text('皮肤下载中…（首次使用需联网下载）'), findsOneWidget);
    });

    testWidgets('未本地化且未下载 → 回退注册表（RemoteChessSkin）预览', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 不传 localSkins / isDownloading → 预览回退 byId（远程皮肤）
      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      expect(find.byType(ChessBoard), findsOneWidget);
      // 预览显示注册表 displayName（catalog 皮肤 '1' = '皮肤 1'）
      expect(find.text(kChessSkinsCatalog[0].displayName), findsWidgets);
    });

    testWidgets('downloadError → 预览显示"下载失败 + 重试"（不渲染棋盘）', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(
          initialSkinId: '1',
          downloadError: (id) => id == '1' ? '下载失败，请检查网络后重试' : null,
        ),
      );
      await tester.pump();

      expect(find.text('下载失败，请检查网络后重试'), findsOneWidget);
      expect(find.text('下载失败，可点击重试'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsWidgets);
      expect(find.byType(ChessBoard), findsNothing, reason: '下载失败不渲染棋盘，显示重试');
    });

    testWidgets('downloadError + 点重试 → onRetryDownload 触发', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final retried = <String>[];
      await tester.pumpWidget(
        host(
          initialSkinId: '1',
          downloadError: (id) => id == '1' ? 'boom' : null,
          onRetryDownload: (id) => retried.add(id),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(retried, ['1'], reason: '重试按钮应触发 onRetryDownload 重新下载');
    });
  });

  // ─────────────── 自定义棋盘颜色（boardPalette 优先级：自定义 > 主题） ───────────────

  group('ChessSkinSettingsPage 自定义棋盘颜色', () {
    /// 读取预览棋盘当前的 boardPalette。
    BoardPalette? previewPalette(WidgetTester tester) =>
        tester.widget<ChessBoard>(find.byType(ChessBoard)).boardPalette;

    testWidgets('页面渲染含"自定义棋盘颜色"区（预设 + 跟随主题 + 自定义色）', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      expect(find.text('自定义棋盘颜色'), findsOneWidget);
      expect(find.text('经典木色'), findsOneWidget);
      expect(find.text('绿色棋盘'), findsOneWidget);
      expect(find.text('灰蓝棋盘'), findsOneWidget);
      expect(find.text('跟随主题'), findsOneWidget);
      expect(find.text('自定义色…'), findsOneWidget);
    });

    testWidgets('点击预设 → 预览棋盘 palette 实时更新 + onPaletteChanged 回调',
        (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      BoardPalette? changed;
      await tester.pumpWidget(host(
        initialSkinId: '1',
        onPaletteChanged: (p) => changed = p,
      ));
      await tester.pump();

      // 初始无自定义 → 预览棋盘 palette 为 null（跟随主题）
      expect(previewPalette(tester), isNull);

      // 点击"经典木色"预设 → 预览 + 回调同步更新
      await tester.tap(find.text('经典木色'));
      await tester.pump();

      final palette = previewPalette(tester);
      expect(palette, isNotNull, reason: '点预设后预览棋盘应携带自定义配色');
      expect(palette!.lightSquare, const Color(0xFFF0D9B5));
      expect(palette.darkSquare, const Color(0xFFB58863));
      expect(changed?.lightSquare, const Color(0xFFF0D9B5),
          reason: 'onPaletteChanged 应实时回调所选配色');
    });

    testWidgets('initialPalette 非空 → 进入即选中对应预设并预览', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(
        initialSkinId: '1',
        initialPalette: const BoardPalette(
          lightSquare: Color(0xFFAAD751),
          darkSquare: Color(0xFF5D9B44),
        ),
      ));
      await tester.pump();

      expect(previewPalette(tester)?.lightSquare, const Color(0xFFAAD751));
      expect(previewPalette(tester)?.darkSquare, const Color(0xFF5D9B44));
    });

    testWidgets('点击"跟随主题" → 清除自定义（palette = null）+ 回调 null',
        (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      BoardPalette? changed = const BoardPalette(lightSquare: Color(0xFF000000));
      await tester.pumpWidget(host(
        initialSkinId: '1',
        initialPalette: const BoardPalette(
          lightSquare: Color(0xFFF0D9B5),
          darkSquare: Color(0xFFB58863),
        ),
        onPaletteChanged: (p) => changed = p,
      ));
      await tester.pump();
      expect(previewPalette(tester), isNotNull);

      // 点击"跟随主题" → 清除自定义
      await tester.tap(find.text('跟随主题'));
      await tester.pump();

      expect(previewPalette(tester), isNull, reason: '跟随主题 = 清除自定义');
      expect(changed, isNull, reason: '回调 null 通知调用方清除持久化');
    });

    testWidgets('自定义色对话框：确定 → 应用所选配色（默认浅深色板）', (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      BoardPalette? changed;
      await tester.pumpWidget(host(
        initialSkinId: '1',
        onPaletteChanged: (p) => changed = p,
      ));
      await tester.pump();

      // 打开自定义拾色对话框
      await tester.tap(find.text('自定义色…'));
      await tester.pumpAndSettle();
      expect(find.text('浅色格'), findsOneWidget);
      expect(find.text('深色格'), findsOneWidget);

      // 直接确定 → 应用默认浅深色（kSwatches[1] / kSwatches[13]）
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(previewPalette(tester)?.lightSquare, const Color(0xFFF0D9B5));
      expect(previewPalette(tester)?.darkSquare, const Color(0xFFB58863));
      expect(changed?.lightSquare, const Color(0xFFF0D9B5));
    });
  });
}
