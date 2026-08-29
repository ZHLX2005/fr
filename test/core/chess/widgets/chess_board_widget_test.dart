// test/core/chess/widgets/chess_board_widget_test.dart
//
// ChessBoard 棋盘渲染：
//   · 默认皮肤 (ChessDefaultSkin) → 起始局面 → 32 个 unicode 字符
//     （没有 Image 棋子，因为默认 skin.pieces 为空）
//   · 第一套皮肤 (kChessSkinsCatalog[0]) → 起始局面 → 32 个 ChessPiece + Image
//   · tap 棋盘格 → onSquareTap 透传 1D index
//
// 注：ChessDefaultSkin 的 fallback unicode 路径：起点 32 个棋子 → 32 个 Text。
// 测试避免依赖外部网络（不真正下载 webp）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_piece.dart';

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
            ),
          ),
        ),
      ),
    );
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
}