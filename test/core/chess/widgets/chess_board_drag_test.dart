// test/core/chess/core/ui/chess_board_drag_test.dart
//
// ChessBoard 拖动手势层（board-gesture-patterns §2.3 长按拖动 + §3.1 单 GestureDetector）：
//   · 无拖动回调 → 不挂手势层（只读棋盘 tap 行为不变）
//   · onPanStart 命中己方格子 → onDragSquareStart 收到正确 1D index（翻转感知）
//   · onPanUpdate → onDragSquareUpdate 收到悬停格
//   · onPanEnd 松手 → onDragSquareEnd 收到落点格（棋盘外 → null）
//   · tap 仍走 onSquareTap（拖动回调存在时 tap 不被破坏）
//   · 翻转（flipped=true）时 pan 坐标映射到白方视角 1D index
//
// 拖动手势用 tester.startGesture + moveBy + up 模拟（真实 pan 手势序列）。
// 坐标：600x600 棋盘、16 标签边距 → boardSize=568、cell=71；
// 8x8 网格左上 = (16,16)，中心 = 格子中心。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_piece.dart';

/// 记录拖动回调事件。
class _DragLog {
  int? startSquare;
  Offset? startPos;
  int? updateSquare;
  Offset? updatePos;
  int? endSquare;
  Offset? endPos;
  final List<int> taps = [];
  final List<String> updates = [];
}

/// 包 600x600 的 host（labelSpace=16，cell=(600-32)/8=71）。
Widget host({
  required ChessSkin skin,
  required _DragLog log,
  BoardState? state,
  bool flipped = false,
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
            sideToMove: PieceColor.white,
            flipped: flipped,
            onSquareTap: log.taps.add,
            onDragSquareStart: (sq, p) {
              log.startSquare = sq;
              log.startPos = p;
            },
            onDragSquareUpdate: (sq, p) {
              log.updateSquare = sq;
              log.updatePos = p;
              log.updates.add('$sq');
            },
            onDragSquareEnd: (sq, p) {
              log.endSquare = sq;
              log.endPos = p;
            },
          ),
        ),
      ),
    ),
  );
}

/// 某 1D index（白方视角）的格子中心全局坐标（几何推导）。
/// 600x600 棋盘 + 16 标签边距 → boardSize=568、cell=71；8x8 网格左上 =
/// ChessBoard 左上 + (16,16)。空/有子格子都能算。
Offset cellCenter(WidgetTester tester, int idx, {bool flipped = false}) {
  const labelSpace = 16.0;
  const cell = 71.0;
  final topLeft = tester.getTopLeft(find.byType(ChessBoard));
  final row = idx ~/ 8;
  final col = idx % 8;
  final (dcol, drow) = flipped ? (7 - col, 7 - row) : (col, row);
  return Offset(
    topLeft.dx + labelSpace + dcol * cell + cell / 2,
    topLeft.dy + labelSpace + drow * cell + cell / 2,
  );
}

void main() {
  setUp(() => ChessSkinBundle.resetForTest());

  testWidgets('无拖动回调 → 不挂手势层（tap 走原格子 onTapDown）', (tester) async {
    ChessSkinBundle.registerHardcoded();
    final log = _DragLog();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 600,
              child: ChessBoard(
                state: BoardState.initial(),
                skin: ChessSkinBundle.byId(kChessSkinsCatalog[0].id),
                sideToMove: PieceColor.white,
                onSquareTap: log.taps.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(cellCenter(tester, squareToIndex('e2')));
    await tester.pump();
    expect(log.taps, [squareToIndex('e2')], reason: '只读棋盘 tap 透传不变');
  });

  testWidgets('pan 拖己方兵 e2 → start=e2、update 跟随悬停格、end=落点', (tester) async {
    ChessSkinBundle.registerHardcoded();
    final log = _DragLog();
    await tester.pumpWidget(host(
      skin: ChessSkinBundle.byId(kChessSkinsCatalog[0].id),
      log: log,
    ));
    await tester.pump();

    final from = cellCenter(tester, squareToIndex('e2'));
    final to = cellCenter(tester, squareToIndex('e4'));
    final g = await tester.startGesture(from);
    // 分步移动（真实拖动序列）：单次 moveTo 不足以让 pan 识别 + 触发 update
    for (var i = 1; i <= 4; i++) {
      final p = Offset.lerp(from, to, i / 4)!;
      await g.moveTo(p);
      await tester.pump();
    }
    await g.up();
    await tester.pump();

    expect(log.startSquare, squareToIndex('e2'),
        reason: '拖动起点 = 按下格（onPanDown 记忆，非 pan 识别点）');
    expect(log.updates, isNotEmpty, reason: '分步移动应产生 update 事件');
    expect(log.endSquare, squareToIndex('e4'), reason: '松手落点 = 目标格');
    expect(log.endSquare, 36);
    // tap 不应被触发（pan 是拖动，不是 tap）
    expect(log.taps, isEmpty);
  });

  testWidgets('pan 拖出棋盘（8x8 外）→ end=null（调用方按非法弹回）', (tester) async {
    ChessSkinBundle.registerHardcoded();
    final log = _DragLog();
    await tester.pumpWidget(host(
      skin: ChessSkinBundle.byId(kChessSkinsCatalog[0].id),
      log: log,
    ));
    await tester.pump();

    final from = cellCenter(tester, squareToIndex('e2'));
    final g = await tester.startGesture(from);
    // 分步拖出棋盘顶（8x8 网格从 y=16 开始，最终 y<16 → 出界）
    final out = from + const Offset(0, -500);
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(Offset.lerp(from, out, i / 5)!);
      await tester.pump();
    }
    await g.up();
    await tester.pump();

    expect(log.startSquare, squareToIndex('e2'));
    expect(log.endSquare, isNull, reason: '棋盘外松手 → 落点 null');
    expect(log.taps, isEmpty);
  });

  testWidgets('flipped=true：pan 坐标映射回白方视角 1D index', (tester) async {
    ChessSkinBundle.registerHardcoded();
    final log = _DragLog();
    await tester.pumpWidget(host(
      skin: ChessSkinBundle.byId(kChessSkinsCatalog[0].id),
      log: log,
      flipped: true,
    ));
    await tester.pump();

    // 黑方视角：白方 e2 显示在 (7-4, 7-6) = 显示第 1 行第 3 列。
    // 向上移动 1 格 → 显示第 0 行（rank 1）→ 白方视角 row 7 col 4 = idx 60。
    final from = cellCenter(tester, squareToIndex('e2'), flipped: true);
    final g = await tester.startGesture(from);
    // 分步向上移动 1 格（真实拖动序列）
    for (var i = 1; i <= 3; i++) {
      await g.moveBy(const Offset(0, -71 / 3));
      await tester.pump();
    }
    await g.up();
    await tester.pump();

    expect(log.startSquare, squareToIndex('e2'),
        reason: '翻转后 start 仍映射回白方视角 1D index');
    expect(log.endSquare, 60,
        reason: '显示向上 1 格（rank1 行）→ 白方视角 idx 60');
  });

  testWidgets('拖动回调存在时 tap 仍走 onSquareTap（选中-点击两段式不破坏）', (tester) async {
    ChessSkinBundle.registerHardcoded();
    final log = _DragLog();
    await tester.pumpWidget(host(
      skin: ChessSkinBundle.byId(kChessSkinsCatalog[0].id),
      log: log,
    ));
    await tester.pump();

    // tap 不触发任何拖动回调
    await tester.tapAt(cellCenter(tester, squareToIndex('d2')));
    await tester.pump();
    expect(log.taps, [squareToIndex('d2')]);
    expect(log.startSquare, isNull);
    expect(log.endSquare, isNull);
  });
}
