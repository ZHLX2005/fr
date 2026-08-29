// test/core/chess/widgets/promotion_panel_test.dart
//
// PromotionPanel 升变面板 —— 兵到底线时暂停走法，弹面板让玩家选 Q/R/B/N：
//   · 白兵 e7 → e8（升变）→ 面板出现，onMove 未触发
//   · 选 Q → 升变为后，onMove 触发且 promotion == queen，面板消失
//   · 选 R → 升变为车，onMove 触发且 promotion == rook，面板消失
//   · 取消（点遮罩）→ 面板消失，onMove 未触发，未应用走法
//
// 复用 chess_controller_widget_test 的 host() + tapCell() 模式：
//   tapCell 按 GestureDetector 顺序 tap（0..63 = 1D idx）。
// 面板弹出后，棋盘格被面板遮罩盖住（不再可点），按钮需用
// `find.descendant(of: PromotionPanel)` 限定查找：
//   面板内 GestureDetector 顺序 = [遮罩, Q, R, B, N]（DFS 先父后子）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_controller.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/promotion_panel.dart';

void main() {
  setUp(() => ChessSkinBundle.resetForTest());

  /// 升变测试局面：白方 e7 兵（idx 52），黑王 a8（idx 0），e8 空。
  /// 白兵 e7→e8 有 4 个升变候选（Q/R/B/N）。
  final BoardState promoState =
      FenCodec.fromFen('k7/4P3/8/8/8/8/8/4K3 w - - 0 1');

  /// 用 controller 包一层 600x600 的 host，便于 tap at cell.
  Widget host({
    required List<Move> movesSink,
    BoardState? initial,
  }) {
    ChessSkinBundle.registerHardcoded();
    final skin = ChessSkinBundle.byId(kChessSkinsCatalog[0].id);
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 600,
            child: ChessController(
              engine: const ChessEngine(),
              skin: skin,
              onMove: movesSink.add,
              initialState: initial,
            ),
          ),
        ),
      ),
    );
  }

  /// 用 GestureDetector finder 第 idx 个 tap（按 cell 顺序 0..63 = 1D idx）。
  Future<void> tapCell(WidgetTester tester, int idx) async {
    final detectors = find.byType(GestureDetector);
    expect(detectors, findsWidgets);
    await tester.tap(detectors.at(idx));
    await tester.pump();
  }

  /// 走完"选中 e7 → tap e8"两步，回到（可能已弹出面板）的状态。
  Future<void> tapPromotion(WidgetTester tester) async {
    await tapCell(tester, squareToIndex('e7'));
    await tapCell(tester, squareToIndex('e8'));
  }

  /// 面板内的 GestureDetector（限域到 PromotionPanel，避开被遮罩盖住的棋盘格）：
  /// [遮罩, Q, R, B, N]（DFS 先父后子）。
  Finder panelDetectors() => find.descendant(
        of: find.byType(PromotionPanel),
        matching: find.byType(GestureDetector),
      );

  /// 面板上选 Q/R/B/N（candidateIndex = 0..3，跳过第 0 个遮罩）。
  Future<void> selectPromotion(WidgetTester tester, int candidateIndex) async {
    final detectors = panelDetectors();
    expect(detectors, findsNWidgets(5)); // 遮罩 + 4 按钮
    await tester.tap(detectors.at(candidateIndex + 1));
    await tester.pump();
  }
  testWidgets('兵到底线 → 弹升变面板，onMove 未触发', (tester) async {
    final moves = <Move>[];
    await tester.pumpWidget(host(movesSink: moves, initial: promoState));
    await tester.pump();

    await tapPromotion(tester);

    // 面板出现；尚未 emit 任何走法
    expect(find.byType(PromotionPanel), findsOneWidget);
    expect(moves.length, 0);
  });

  testWidgets('选 Q → 升变为后，onMove 触发且 promotion == queen', (tester) async {
    final moves = <Move>[];
    await tester.pumpWidget(host(movesSink: moves, initial: promoState));
    await tester.pump();

    await tapPromotion(tester);
    expect(find.byType(PromotionPanel), findsOneWidget);

    await selectPromotion(tester, 0); // 第一个候选 = queen

    expect(moves.length, 1);
    expect(moves.first.from, squareToIndex('e7'));
    expect(moves.first.to, squareToIndex('e8'));
    expect(moves.first.promotion, PieceType.queen);
    // 面板消失
    expect(find.byType(PromotionPanel), findsNothing);
  });

  testWidgets('选 R → 升变为车，onMove 触发且 promotion == rook', (tester) async {
    final moves = <Move>[];
    await tester.pumpWidget(host(movesSink: moves, initial: promoState));
    await tester.pump();

    await tapPromotion(tester);
    expect(find.byType(PromotionPanel), findsOneWidget);

    await selectPromotion(tester, 1); // 第二个候选 = rook

    expect(moves.length, 1);
    expect(moves.first.promotion, PieceType.rook);
    expect(find.byType(PromotionPanel), findsNothing);
  });

  testWidgets('取消（点遮罩）→ 面板消失，onMove 未触发', (tester) async {
    final moves = <Move>[];
    await tester.pumpWidget(host(movesSink: moves, initial: promoState));
    await tester.pump();

    await tapPromotion(tester);
    expect(find.byType(PromotionPanel), findsOneWidget);

    // 点遮罩（面板内第 0 个 GestureDetector）→ 取消
    final detectors = panelDetectors();
    await tester.tap(detectors.at(0));
    await tester.pump();

    expect(find.byType(PromotionPanel), findsNothing);
    expect(moves.length, 0);
  });
}
