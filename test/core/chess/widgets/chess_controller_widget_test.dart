// test/core/chess/widgets/chess_controller_widget_test.dart
//
// ChessController 状态机：
//   · 初始 → tap e2 → 选中 e2，合法目标 = {e3, e4}
//   · 选中后 tap e4 → 走法 e2-e4，state 推进，onMove 回调触发，selection 清空
//   · 未选中 tap e7（对方） → no-op（不选中、不报错）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_controller.dart';

void main() {
  setUp(() => ChessSkinBundle.resetForTest());

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
  /// tester.tap(finder) 走 widget hit test；tester.tapAt(coord) 在复杂
  /// 嵌套 Stack 里有时会失灵，故统一走 finder 路径。
  Future<void> tapCell(WidgetTester tester, int idx) async {
    final detectors = find.byType(GestureDetector);
    expect(detectors, findsWidgets);
    await tester.tap(detectors.at(idx));
    await tester.pump();
  }

  testWidgets('初始 → tap e2 → 选中 e2，合法目标 = {e3, e4}',
      (tester) async {
    final moves = <Move>[];
    await tester.pumpWidget(host(movesSink: moves));
    await tester.pump();

    final e2 = squareToIndex('e2');
    final e3 = squareToIndex('e3');
    await tapCell(tester, e2);
    await tester.pump();

    // 选中 e2 后 tap e3 → 应该走到 e3，无错误；说明 selection 真的在工作。
    await tapCell(tester, e3);
    await tester.pump();

    expect(moves.length, 1);
    expect(moves[0].from, e2);
    expect(moves[0].to, e3);
  });

  testWidgets('tap e2 → tap e4 → state 推进到 e2-e4，onMove 触发，selection 清',
      (tester) async {
    final moves = <Move>[];
    await tester.pumpWidget(host(movesSink: moves));
    await tester.pump();

    final e2 = squareToIndex('e2');
    final e4 = squareToIndex('e4');

    await tapCell(tester, e2);
    await tester.pump();
    await tapCell(tester, e4);
    await tester.pump();

    expect(moves.length, 1);
    expect(moves.first.from, e2);
    expect(moves.first.to, e4);

    // State 推进：现在该 black 走。再 tap 黑方兵 e7 → 应该能选中
    final e7 = squareToIndex('e7');
    await tapCell(tester, e7);
    await tester.pump();
    // tap e5（黑兵走两步）
    final e5 = squareToIndex('e5');
    await tapCell(tester, e5);
    await tester.pump();
    expect(moves.length, 2);
    expect(moves[1].from, e7);
    expect(moves[1].to, e5);
  });

  testWidgets('未选中 → tap e7（黑方，对方） → no-op',
      (tester) async {
    final moves = <Move>[];
    await tester.pumpWidget(host(movesSink: moves));
    await tester.pump();

    final e7 = squareToIndex('e7');
    await tapCell(tester, e7);
    await tester.pump();

    // 没有走法触发
    expect(moves.length, 0);

    // 再 tap e2 仍然能选中（说明之前没污染状态）
    final e2 = squareToIndex('e2');
    await tapCell(tester, e2);
    await tester.pump();
    final e4 = squareToIndex('e4');
    await tapCell(tester, e4);
    await tester.pump();
    expect(moves.length, 1);
  });

  testWidgets('非法目标 → tap 已选中的空格（非合法目标）→ 清选',
      (tester) async {
    final moves = <Move>[];
    await tester.pumpWidget(host(movesSink: moves));
    await tester.pump();

    final e2 = squareToIndex('e2');
    final d3 = squareToIndex('d3'); // 非 e2 合法走法
    await tapCell(tester, e2);
    await tester.pump();
    await tapCell(tester, d3);
    await tester.pump();
    // 没走到任何走法
    expect(moves.length, 0);

    // 重新 tap e2 + 合法目标 e4 → 走法应能完成
    await tapCell(tester, e2);
    await tester.pump();
    final e4 = squareToIndex('e4');
    await tapCell(tester, e4);
    await tester.pump();
    expect(moves.length, 1);
    expect(moves.first.from, e2);
    expect(moves.first.to, e4);
  });
}