// test/core/chess/replay/chess_game_replay_page_test.dart
//
// ChessGameReplayPage 整局离线回放页：
//   · 默认从终局开始（快照列表最后一档选中）
//   · 快照列表点选任意一步 → 直接跳到该局面（核心需求）
//   · 步进 / 播放 / 退出
//   · 截断提示 + 终局徽标

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_replay_page.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';

const String _kStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

ChessGameRecord _record({
  List<String> moves = const ['e2e4', 'e7e5', 'g1f3'],
  String status = 'checkmate',
}) =>
    ChessGameRecord(
      id: 'game-test-1',
      title: '对局 09-19 23:19',
      initialFen: _kStartFen,
      uciMoves: moves,
      status: status,
      roomCode: '999999',
      savedAt: '2026-09-19T15:19:54Z',
    );

/// 主棋盘 = 树中第一个 ChessBoard（主棋盘在快照缩略列表之前 build）。
ChessBoard mainBoard(WidgetTester tester) => tester.widget<ChessBoard>(
      find.byType(ChessBoard).first,
    );

Future<void> pumpPage(WidgetTester tester, ChessGameRecord record) async {
  // 经由真实 push 进入（页面 pop 语义依赖 Navigator 栈）。
  late final BuildContext navCtx;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) {
          navCtx = ctx;
          return TextButton(
            onPressed: () => Navigator.of(navCtx).push(
              MaterialPageRoute(
                builder: (_) => ChessGameReplayPage(record: record),
              ),
            ),
            child: const Text('OPEN'),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认从终局开始：主棋盘渲染终局局面（3 手后轮黑）', (tester) async {
    await pumpPage(tester, _record());

    expect(find.text('对局 09-19 23:19'), findsOneWidget);
    expect(mainBoard(tester).state.sideToMove, PieceColor.black);
    expect(mainBoard(tester).lastMove, isNotNull, reason: '终局显示上一步高亮');
  });

  testWidgets('快照列表：开局/每手/终局 全档可见，终局选中高亮', (tester) async {
    await pumpPage(tester, _record());

    expect(find.text('开局'), findsOneWidget);
    expect(find.text('第 1 手'), findsOneWidget);
    expect(find.text('第 2 手'), findsOneWidget);
    expect(find.text('终局 · 3'), findsOneWidget);
    // 快照缩略棋盘：主棋盘 + 4 档 = 5 个 ChessBoard。
    expect(find.byType(ChessBoard), findsNWidgets(5));
  });

  testWidgets('点「开局」快照 → 主棋盘直接跳到初始局面（核心交互）', (tester) async {
    await pumpPage(tester, _record());

    await tester.tap(find.text('开局'));
    await tester.pump();

    final board = mainBoard(tester);
    expect(board.state.sideToMove, PieceColor.white,
        reason: '初始局面轮白');
    expect(board.lastMove, isNull, reason: '初始局面无上一步高亮');
    expect(board.state.pieceTypeAt(squareToIndex('e2')), PieceType.pawn);
  });

  testWidgets('点「第 2 手」快照 → 跳到 2 手后局面（e5 落位、轮白）', (tester) async {
    await pumpPage(tester, _record());

    await tester.tap(find.text('第 2 手'));
    await tester.pump();

    final board = mainBoard(tester);
    expect(board.state.sideToMove, PieceColor.white);
    expect(board.state.pieceTypeAt(squareToIndex('e5')), PieceType.pawn,
        reason: '第 2 手（e7e5）后黑兵在 e5');
    expect(board.state.isEmpty(squareToIndex('e7')), isTrue);
  });

  testWidgets('步进控制：跳开局后「下一步」推进一手', (tester) async {
    await pumpPage(tester, _record());

    await tester.tap(find.text('开局'));
    await tester.pump();
    await tester.tap(find.byTooltip('下一步'));
    await tester.pump();

    expect(mainBoard(tester).state.pieceTypeAt(squareToIndex('e4')),
        PieceType.pawn, reason: '前进一步 = e2e4 完成');
  });

  testWidgets('终局态「下一步」/「跳到终局」禁用；跳开局后启用', (tester) async {
    await pumpPage(tester, _record());

    IconButton nextAtEnd() => tester.widget<IconButton>(
          find.ancestor(
            of: find.byIcon(Icons.chevron_right),
            matching: find.byType(IconButton),
          ),
        );
    expect(nextAtEnd().onPressed, isNull, reason: '已在终局 → 下一步禁用');

    await tester.tap(find.text('开局'));
    await tester.pump();
    expect(nextAtEnd().onPressed, isNotNull);
  });

  testWidgets('自动播放：点 ▶ 后定时推进（ pump 模拟 800ms 节拍）', (tester) async {
    await pumpPage(tester, _record());
    await tester.tap(find.text('开局'));
    await tester.pump();

    await tester.tap(find.byTooltip('自动播放'));
    await tester.pump();
    // 800ms 一拍：推进 2 拍。
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    expect(mainBoard(tester).state.pieceTypeAt(squareToIndex('e5')),
        PieceType.pawn, reason: '两拍后走到第 2 手（e7e5）');

    // 播放中再点（⏸）→ 暂停。
    await tester.tap(find.byTooltip('暂停'));
    await tester.pump();
    expect(find.byTooltip('自动播放'), findsOneWidget, reason: '播放键复位 ▶');
  });

  testWidgets('终局徽标：status checkmate → AppBar 显示「将杀」', (tester) async {
    await pumpPage(tester, _record());
    expect(find.text('将杀'), findsOneWidget);
  });

  testWidgets('谱尾截断：畸形 uci → 顶部提示条（只回放到合法前缀）', (tester) async {
    await pumpPage(
      tester,
      _record(moves: const ['e2e4', 'zz99']),
    );

    expect(find.textContaining('谱尾 1 手无法解析'), findsOneWidget);
    // 合法前缀 1 手 → 终局 = 第 1 手。
    expect(find.text('终局 · 1'), findsOneWidget);
  });

  testWidgets('退出回放 → pop 返回', (tester) async {
    await pumpPage(tester, _record());
    await tester.tap(find.text('退出回放'));
    await tester.pumpAndSettle();

    expect(find.byType(ChessGameReplayPage), findsNothing,
        reason: '页面已关闭');
  });
}
