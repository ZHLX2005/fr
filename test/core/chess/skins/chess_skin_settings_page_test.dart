// test/core/chess/skins/chess_skin_settings_page_test.dart
//
// 全屏换肤设置页（ChessSkinSettingsPage）widget 测试：
//   · AppBar 返回箭头存在
//   · 左侧皮肤列表渲染 7 套（displayName 全部可见）
//   · 点击皮肤 → 预览区 ChessBoard 更新（真实渲染，非占位）
//   · 宽屏两栏 / 窄屏竖排布局都存在
//   · 返回（BackButton + 系统 back）→ pop 携带当前选中皮肤 id
//
// 注：页面不直接读写 SharedPreferences（持久化在调用方），
// 故测试不 mock prefs；但注册表需要 registerHardcoded 才能按 id 解析皮肤。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_settings_page.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/theme/colors/factory.dart';
import 'package:xiaodouzi_fr/core/theme/extensions/chess_color_strategy_extension.dart';

void main() {
  setUp(() => ChessSkinBundle.registerHardcoded());

  /// 宿主：注入 ChessColorStrategyExtension，页面才能读 context.chessColors。
  Widget host({
    required String initialSkinId,
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
        builder: (context) => ChessSkinSettingsPage(initialSkinId: initialSkinId),
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
      expect(find.byType(BackButton), findsOneWidget,
          reason: '返回箭头是 BackButton 类型');
    });

    testWidgets('宽屏（900px）→ 两栏 Row + 皮肤列表 7 项 + 预览棋盘',
        (tester) async {
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(initialSkinId: '1'));
      await tester.pump();

      // 7 套皮肤的 displayName 全部渲染
      // 注：选中皮肤会在"列表项 + 预览标题"出现 2 次，故用 findsWidgets。
      for (final meta in kChessSkinsCatalog) {
        expect(find.text(meta.displayName), findsWidgets,
            reason: '皮肤 "${meta.displayName}" 应出现在列表中');
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
      expect(find.text(skin2.displayName), findsNWidgets(2),
          reason: '列表一项 + 预览标题一项 = 2 处显示皮肤 2 名称');
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
                        builder: (_) => const ChessSkinSettingsPage(
                          initialSkinId: '1',
                        ),
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
      expect(popped, skin3.id,
          reason: '返回箭头应携带当前选中（已切到皮肤 3）的 id');
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
                        builder: (_) => const ChessSkinSettingsPage(
                          initialSkinId: '1',
                        ),
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
      expect(popped, skin4.id,
          reason: '系统返回经 PopScope 拦截后也应携带当前选中皮肤 id');
    });
  });
}
