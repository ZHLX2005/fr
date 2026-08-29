// test/core/chess/widgets/chess_board_widget_test.dart
//
// ChessBoard 棋盘渲染：
//   · 默认皮肤 (ChessDefaultSkin) → 起始局面 → 32 个 unicode 字符
//     （没有 Image 棋子，因为默认 skin.pieces 为空）
//   · 第一套皮肤 (kChessSkinsCatalog[0]) → 起始局面 → 32 个 ChessPiece + Image
//   · tap 棋盘格 → onSquareTap 透传 1D index
//   · boardPalette（用户自定义）覆盖主题两色格 —— 优先级：自定义 > 主题；
//     只覆盖浅色格时深色格仍走主题（null → 主题兜底）
//
// 注：ChessDefaultSkin 的 fallback unicode 路径：起点 32 个棋子 → 32 个 Text。
// 测试避免依赖外部网络（不真正下载 webp）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/board_palette.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_piece.dart';
import 'package:xiaodouzi_fr/core/theme/colors/strategy/chess_color_strategy/themes/default.dart';

void main() {
  setUp(() => ChessSkinBundle.resetForTest());

  /// 套主题 / 默认皮肤的宿主：600x600 让棋盘足够大。
  Widget host({
    required ChessSkin skin,
    BoardState? state,
    PieceColor sideToMove = PieceColor.white,
    int? selectedSquare,
    Set<int> legalTargets = const <int>{},
    Move? lastMove,
    void Function(int square)? onSquareTap,
    BoardPalette? boardPalette,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 600,
            child: ChessBoard(
              state: state ?? BoardState.initial(),
              skin: skin,
              sideToMove: sideToMove,
              selectedSquare: selectedSquare,
              legalTargets: legalTargets,
              lastMove: lastMove,
              onSquareTap: onSquareTap,
              boardPalette: boardPalette,
            ),
          ),
        ),
      ),
    );
  }

  /// 统计 Container 中 BoxDecoration.color == [color] 的格子数。
  int countSquaresOfColor(WidgetTester tester, Color color) {
    var count = 0;
    for (final c in tester.widgetList<Container>(find.byType(Container))) {
      final deco = c.decoration;
      if (deco is BoxDecoration && deco.color == color) count++;
    }
    return count;
  }

  testWidgets('默认皮肤 + 初始局面 → 32 个 Text (unicode fallback)', (tester) async {
    await tester.pumpWidget(host(skin: const ChessDefaultSkin()));
    await tester.pump();
    // 起点 = 32 个棋子（每方 16）。unicode 渲染走 Text。
    expect(find.byType(Text), findsWidgets);
    // 没有 Image 棋子（默认 skin.pieces 为空）
    expect(find.byType(ChessPiece), findsNothing);
  });

  testWidgets('皮肤 1 + 初始局面 → 32 个 ChessPiece + 32 个 Image', (tester) async {
    ChessSkinBundle.registerHardcoded();
    final skin = kChessSkinsCatalog[0];
    await tester.pumpWidget(host(skin: ChessSkinBundle.byId(skin.id)));
    await tester.pump();
    expect(find.byType(ChessPiece), findsNWidgets(32));
    // ChessPiece 内部就是 Image widget；这里每个 ChessPiece 渲染一个 Image
    expect(find.byType(Image), findsNWidgets(32));
  });

  testWidgets('tap 棋盘格 → onSquareTap 收到正确 1D index',
      (tester) async {
    ChessSkinBundle.registerHardcoded();
    final skin = ChessSkinBundle.byId(kChessSkinsCatalog[0].id);
    int? lastTap;
    await tester.pumpWidget(host(
      skin: skin,
      onSquareTap: (sq) => lastTap = sq,
    ));
    await tester.pump();

    // 用 GestureDetector finder tap 第 idx 个；走 widget hit test 路径，
    // 比 tester.tapAt(coord) 在嵌套 Stack 里更稳定。
    final detectors = find.byType(GestureDetector);
    expect(detectors, findsWidgets);
    // a1 = 白方底线左下，1D idx = rowFromRank(1) * 8 + 0 = 7 * 8 + 0 = 56
    await tester.tap(detectors.at(56));
    await tester.pump();
    expect(lastTap, 56,
        reason: 'a1 (白方底线左下) 应该 1D idx = 56');
  });

  testWidgets('selectedSquare + legalTargets 不抛异常', (tester) async {
    await tester.pumpWidget(host(
      skin: const ChessDefaultSkin(),
      selectedSquare: squareToIndex('e2'),
      legalTargets: {squareToIndex('e3'), squareToIndex('e4')},
    ));
    await tester.pump();
    expect(find.byType(ChessBoard), findsOneWidget);
  });

  testWidgets('黑方视角 (sideToMove=black) → 棋盘渲染（不抛异常）',
      (tester) async {
    ChessSkinBundle.registerHardcoded();
    final skin = ChessSkinBundle.byId(kChessSkinsCatalog[0].id);
    await tester.pumpWidget(host(
      skin: skin,
      sideToMove: PieceColor.black,
    ));
    await tester.pump();
    expect(find.byType(ChessBoard), findsOneWidget);
  });

  // ─────────────── boardPalette：用户自定义 > 主题 ───────────────

  testWidgets('boardPalette 覆盖主题两色格（32 浅 + 32 深全替换）', (tester) async {
    const light = Color(0xFFFF0000); // 自定义红
    const dark = Color(0xFF0000FF); // 自定义蓝
    await tester.pumpWidget(host(
      skin: const ChessDefaultSkin(),
      boardPalette: const BoardPalette(lightSquare: light, darkSquare: dark),
    ));
    await tester.pump();

    // 64 格 = 32 浅 + 32 深，全部用自定义色（用户自定义 > 主题）。
    expect(countSquaresOfColor(tester, light), 32,
        reason: '32 个浅色格应为自定义红色');
    expect(countSquaresOfColor(tester, dark), 32,
        reason: '32 个深色格应为自定义蓝色');

    // 主题默认两色不应再出现（被自定义完全覆盖）。
    final scheme =
        Theme.of(tester.element(find.byType(ChessBoard))).colorScheme;
    final themeLight = DefaultChessColorStrategy.of(scheme).lightSquare;
    final themeDark = DefaultChessColorStrategy.of(scheme).darkSquare;
    expect(countSquaresOfColor(tester, themeLight), 0,
        reason: '主题浅色格被自定义覆盖后不应出现');
    expect(countSquaresOfColor(tester, themeDark), 0,
        reason: '主题深色格被自定义覆盖后不应出现');
  });

  testWidgets('boardPalette 只覆盖浅色格 → 深色格仍走主题（null → 主题兜底）',
      (tester) async {
    const light = Color(0xFF00FF00); // 只自定义浅色格
    await tester.pumpWidget(host(
      skin: const ChessDefaultSkin(),
      boardPalette: const BoardPalette(lightSquare: light),
    ));
    await tester.pump();

    expect(countSquaresOfColor(tester, light), 32,
        reason: '浅色格用自定义绿色');
    // 深色格未覆盖 → 回退主题默认（darkSquareFrom(scheme)）。
    final scheme =
        Theme.of(tester.element(find.byType(ChessBoard))).colorScheme;
    final themeDark = DefaultChessColorStrategy.of(scheme).darkSquare;
    expect(countSquaresOfColor(tester, themeDark), 32,
        reason: '深色格未覆盖 → 32 格仍是主题默认色');
  });

  testWidgets('boardPalette == null → 与旧版行为一致（全部主题色）', (tester) async {
    await tester.pumpWidget(host(skin: const ChessDefaultSkin()));
    await tester.pump();

    final scheme =
        Theme.of(tester.element(find.byType(ChessBoard))).colorScheme;
    final themeLight = DefaultChessColorStrategy.of(scheme).lightSquare;
    final themeDark = DefaultChessColorStrategy.of(scheme).darkSquare;
    expect(countSquaresOfColor(tester, themeLight), 32);
    expect(countSquaresOfColor(tester, themeDark), 32);
  });

  testWidgets('selectedSquare 走主题高亮（palette 未覆盖 selectedSquare）',
      (tester) async {
    const light = Color(0xFFFF0000);
    await tester.pumpWidget(host(
      skin: const ChessDefaultSkin(),
      selectedSquare: squareToIndex('e2'),
      boardPalette: const BoardPalette(
        lightSquare: light,
        darkSquare: Color(0xFF0000FF),
      ),
    ));
    await tester.pump();

    final scheme =
        Theme.of(tester.element(find.byType(ChessBoard))).colorScheme;
    final themeSelected = DefaultChessColorStrategy.of(scheme).selectedSquare;
    expect(countSquaresOfColor(tester, themeSelected), 1,
        reason: '选中格高亮未自定义 → 仍走主题 selectedSquare');
  });
}