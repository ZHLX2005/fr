// ChessPlayer 位移动画的回归测试。
//
// 背景：这个 widget 的注释长期写着"使用 AnimatedContainer 实现 200ms 弹性动画"，
// 但位移用的是静态 Positioned，AnimatedContainer 只动 width/height/decoration
// 而这些从不变化 —— 也就是说棋子其实一直在瞬移，动画是空转的，肉眼不容易发现。
// 这里断言"中途必须在起点和终点之间"，把这种静默失效钉住。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';
import 'package:xiaodouzi_fr/core/surround_game/widgets/chess_player.dart';

const double _cellSize = 30;
const double _distance = _cellSize * 1.25;
const double _pieceSize = _cellSize * 0.7;

/// 某个 cellId 静止时棋子的左上角
Offset _restTopLeft(int cellId) {
  const cols = SurroundGameConstants.boardCols;
  final x = (cellId % cols).toDouble();
  final y = (cellId ~/ cols).toDouble();
  return Offset(
    x * _distance + (_cellSize - _pieceSize) / 2,
    y * _distance + (_cellSize - _pieceSize) / 2,
  );
}

Widget _host({required int cellId, Offset? dragOffset}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      width: 400,
      height: 400,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ChessPlayer(
            cellId: cellId,
            cellSize: _cellSize,
            color: const Color(0xFF3B82F6),
            dragOffset: dragOffset,
          ),
        ],
      ),
    ),
  );
}

/// 读出当前帧棋子的左上角
Offset _currentTopLeft(WidgetTester tester) {
  final p = tester.widget<Positioned>(find.byType(Positioned));
  return Offset(p.left!, p.top!);
}

void main() {
  group('ChessPlayer 位移', () {
    testWidgets('初次挂载直接就位，不会开局先飞一次', (tester) async {
      await tester.pumpWidget(_host(cellId: 4));
      expect(_currentTopLeft(tester), _restTopLeft(4));
    });

    testWidgets('换格时中途必须处在起点与终点之间（不是瞬移）', (tester) async {
      await tester.pumpWidget(_host(cellId: 4));
      final from = _restTopLeft(4);
      final to = _restTopLeft(13); // 正下方一格

      await tester.pumpWidget(_host(cellId: 13));
      // 走到动画中段
      await tester.pump(SurroundGameConstants.pieceMoveDuration ~/ 2);

      final mid = _currentTopLeft(tester);
      expect(mid.dy, greaterThan(from.dy),
          reason: '中途还停在起点 —— 位移动画没生效');
      expect(mid.dy, lessThan(to.dy), reason: '中途已经到终点 —— 棋子是瞬移的');

      await tester.pumpAndSettle();
      expect(_currentTopLeft(tester), to);
    });

    testWidgets('飞行中途棋子被"抬起"（放大），落地后恢复', (tester) async {
      await tester.pumpWidget(_host(cellId: 4));
      double scaleOf(WidgetTester t) =>
          t.widget<Transform>(find.byType(Transform)).transform.storage[0];

      expect(scaleOf(tester), moreOrLessEquals(1, epsilon: 0.001));

      await tester.pumpWidget(_host(cellId: 13));
      await tester.pump(SurroundGameConstants.pieceMoveDuration ~/ 2);
      expect(scaleOf(tester), greaterThan(1.05), reason: '中途没有抬起效果');

      await tester.pumpAndSettle();
      expect(scaleOf(tester), moreOrLessEquals(1, epsilon: 0.001));
    });
  });

  group('ChessPlayer 拖拽', () {
    testWidgets('dragOffset 非空时棋子跟手，不跑动画', (tester) async {
      await tester.pumpWidget(_host(cellId: 4));

      const finger = Offset(200, 150);
      await tester.pumpWidget(_host(cellId: 4, dragOffset: finger));
      await tester.pump();

      // 手指位置是棋子**中心**
      final topLeft = _currentTopLeft(tester);
      expect(topLeft.dx + _pieceSize / 2, moreOrLessEquals(finger.dx, epsilon: 0.01));
      expect(topLeft.dy + _pieceSize / 2, moreOrLessEquals(finger.dy, epsilon: 0.01));
    });

    testWidgets('松手后从手指位置滑向落点，而不是从原格子重走一遍', (tester) async {
      await tester.pumpWidget(_host(cellId: 4));

      // 拖到 13 号格附近
      final target = _restTopLeft(13) + const Offset(_pieceSize / 2, _pieceSize / 2);
      final finger = target + const Offset(3, 3);
      await tester.pumpWidget(_host(cellId: 4, dragOffset: finger));
      await tester.pump();

      // 松手 → cellId 变成落点，dragOffset 同时置空
      await tester.pumpWidget(_host(cellId: 13));
      await tester.pump(const Duration(milliseconds: 16));

      final justAfterRelease = _currentTopLeft(tester);
      // 起点应该贴着手指，而不是回到 4 号格
      expect(
        (justAfterRelease - _restTopLeft(4)).distance,
        greaterThan(_distance),
        reason: '松手后棋子跳回了原格子，会看到"闪一下再重走"',
      );
      expect((justAfterRelease - _restTopLeft(13)).distance, lessThan(_distance));

      await tester.pumpAndSettle();
      expect(_currentTopLeft(tester), _restTopLeft(13));
    });
  });
}
