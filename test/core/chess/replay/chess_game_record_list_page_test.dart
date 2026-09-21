// test/core/chess/replay/chess_game_record_list_page_test.dart
//
// ChessGameRecordListPage 对局回放库列表页：
//   · 已保存整局卡片（标题/日期/手数/终局徽标）
//   · 空库提示
//   · 点卡片 → push ChessGameReplayPage
//   · 删除（确认弹窗）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record_list_page.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record_store.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_replay_page.dart';

const String _kStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

ChessGameRecord _record(String id, {String status = 'checkmate'}) =>
    ChessGameRecord(
      id: id,
      title: '对局 $id',
      initialFen: _kStartFen,
      uciMoves: const ['e2e4', 'e7e5', 'g1f3', 'b8c6'],
      status: status,
      roomCode: '999999',
      savedAt: '2026-09-19T15:19:54Z',
    );

/// 内存 fake store —— testWidgets 的 FakeAsync zone 里 await 真实文件 IO
/// 会因 IO 完成事件不进 fake 时钟而挂死，widget 测试必须绕开磁盘
/// （落盘 / 倒序 / 损坏文件等真实 IO 语义已在 store 单测覆盖）。
class _FakeStore extends ChessGameRecordStore {
  _FakeStore() : super(isWeb: false);

  final List<ChessGameRecord> records = [];

  @override
  Future<List<ChessGameRecord>> loadAll() async =>
      List.of(records)
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  Future<void> delete(String id) async =>
      records.removeWhere((r) => r.id == id);
}

void main() {
  Future<void> pumpPage(WidgetTester tester, _FakeStore store) async {
    await tester.pumpWidget(
      MaterialApp(home: ChessGameRecordListPage(store: store)),
    );
    await tester.pump(); // loading
    await tester.pump(); // 数据到达
  }

  testWidgets('已保存整局 → 卡片展示标题 / 手数 / 终局徽标', (tester) async {
    final store = _FakeStore()
      ..records.addAll([
        _record('game-a', status: 'resigned'),
        _record('game-b', status: 'draw'),
      ]);

    await pumpPage(tester, store);

    expect(find.text('对局 game-a'), findsOneWidget);
    expect(find.text('对局 game-b'), findsOneWidget);
    expect(find.text('4 手'), findsNWidgets(2));
    expect(find.text('认输'), findsOneWidget);
    expect(find.text('和棋'), findsOneWidget);
    expect(find.text('2026-09-19 23:19'), findsNWidgets(2),
        reason: 'savedAt UTC → 本地 +8 展示');
  });

  testWidgets('空库 → 空态提示', (tester) async {
    await pumpPage(tester, _FakeStore());
    expect(find.textContaining('暂无已保存的对局'), findsOneWidget);
  });

  testWidgets('点卡片 → push ChessGameReplayPage（默认从终局开始）', (tester) async {
    final store = _FakeStore()..records.add(_record('game-a'));

    await pumpPage(tester, store);
    await tester.tap(find.text('对局 game-a'));
    await tester.pumpAndSettle();

    expect(find.byType(ChessGameReplayPage), findsOneWidget);
    expect(find.text('终局 · 4'), findsOneWidget,
        reason: '回放页从终局开始（4 手谱）');
  });

  testWidgets('删除：确认弹窗 → 删除 → 列表刷新为空', (tester) async {
    final store = _FakeStore()..records.add(_record('game-a'));

    await pumpPage(tester, store);
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('确定删除「对局 game-a」？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无已保存的对局'), findsOneWidget,
        reason: '删除后列表刷新为空');
    expect(store.records, isEmpty);
  });

  testWidgets('删除取消 → 条目保留', (tester) async {
    final store = _FakeStore()..records.add(_record('game-a'));

    await pumpPage(tester, store);
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(find.text('对局 game-a'), findsOneWidget);
  });
}
