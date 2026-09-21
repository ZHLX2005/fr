// test/core/chess/replay/chess_replay_export_test.dart
//
// id61 回放一级化 · 残局快照导出回归：
//   · 回放页接上「导出残局快照」（快照 = 残局，概念统一）
//   · 导出 payload：id / title / snapshotLabel / lineageMoves / lineageMoveIndex
//   · 幂等：同记录同手数重复导出 → "残局已更新"，不重复落盘
//   · 皮肤回退：prefs 不可用时保持默认皮肤（页面不炸）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/chess/engine/fen_codec.dart';
import 'package:xiaodouzi_fr/core/chess/endgame/chess_endgame.dart';
import 'package:xiaodouzi_fr/core/chess/endgame/chess_endgame_store.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_replay_page.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';

const String _kStartFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

ChessGameRecord _record() => ChessGameRecord(
      id: 'game-test-1',
      title: '对局 09-21 12:00',
      initialFen: _kStartFen,
      uciMoves: const ['e2e4', 'e7e5', 'g1f3'],
      status: 'checkmate',
      roomCode: '999999',
      savedAt: '2026-09-21T04:00:00Z',
    );

/// 内存版残局 store（替代真实 `<documents>/` IO —— testWidgets FakeAsync 下
/// 真实文件 IO 永不完成，会永久挂起）。
class FakeEndgameStore extends ChessEndgameStore {
  FakeEndgameStore() : super(isWeb: false);

  final List<ChessEndgame> saved = [];

  @override
  Future<bool> existsLocal(String id) async =>
      saved.any((e) => e.id == id);

  @override
  Future<void> save(ChessEndgame e) async {
    saved.removeWhere((x) => x.id == e.id);
    saved.add(e);
  }
}

Future<void> pumpPage(
  WidgetTester tester,
  ChessGameRecord record,
  FakeEndgameStore store,
) async {
  // 直接作为 home 渲染（经 push 进二级路由时 ScaffoldMessenger 的
  // SnackBar 自动消失定时器在 FakeAsync 下表现异常，无法用假时钟送走）。
  await tester.pumpWidget(
    MaterialApp(
      home: ChessGameReplayPage(record: record, endgameStore: store),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认在终局导出 → 快照落盘：id/title/label/lineage 正确', (tester) async {
    final store = FakeEndgameStore();
    await pumpPage(tester, _record(), store);

    await tester.tap(find.byTooltip('导出残局快照'));
    await tester.pumpAndSettle();

    expect(find.text('已保存到残局库：残局·第 3 手'), findsOneWidget);
    expect(store.saved, hasLength(1));
    final eg = store.saved.single;
    expect(eg.id, 'eg-rp-game-test-1-m3');
    expect(eg.title, '残局·第 3 手');
    expect(eg.snapshots, hasLength(1));
    final snap = eg.snapshots.single;
    expect(snap.label, '第 3 手后');
    expect(snap.lineageMoves, ['e2e4', 'e7e5', 'g1f3']);
    expect(snap.lineageMoveIndex, 3);
    // fen = 终局局面 FEN（与主棋盘状态一致）。
    final board = tester.widget<ChessBoard>(
      find.byType(ChessBoard).first,
    );
    expect(snap.fen, FenCodec.toFen(board.state));
  });

  testWidgets('跳到开局导出 → 初始局面快照（lineage 为空，label 初始局面）', (tester) async {
    final store = FakeEndgameStore();
    await pumpPage(tester, _record(), store);

    await tester.tap(find.text('开局'));
    await tester.pump();
    await tester.tap(find.byTooltip('导出残局快照'));
    await tester.pumpAndSettle();

    expect(find.text('已保存到残局库：残局·初始局面'), findsOneWidget);
    expect(store.saved, hasLength(1));
    final snap = store.saved.single.snapshots.single;
    expect(store.saved.single.id, 'eg-rp-game-test-1-m0');
    expect(snap.label, '初始局面');
    expect(snap.lineageMoves, isEmpty);
    expect(snap.lineageMoveIndex, 0);
  });

  testWidgets('同手数重复导出 → 幂等："残局已更新"，仍只有一条', (tester) async {
    final store = FakeEndgameStore();
    await pumpPage(tester, _record(), store);

    await tester.tap(find.byTooltip('导出残局快照'));
    await tester.pump();
    await tester.pump();
    // 首条 SnackBar 可见。
    expect(find.textContaining('已保存到残局库'), findsOneWidget);
    // FakeAsync 下本页 SnackBar 的自动消失定时器行为异常（探针实测：
    // 15s 假时钟推进仍不退场；真实设备为标准 4s 自动消失），假时钟
    // 送不走 → 用 clearSnackBars 确定性清除，避免第二条被排队挡住。
    final pageCtx = tester.element(find.byType(ChessGameReplayPage));
    ScaffoldMessenger.of(pageCtx).clearSnackBars();
    await tester.pumpAndSettle();
    expect(find.textContaining('已保存到残局库'), findsNothing);

    // 同手数再导出（同 id）→ 幂等提示。
    await tester.tap(find.byTooltip('导出残局快照'));
    await tester.pumpAndSettle();

    expect(find.textContaining('残局已更新'), findsOneWidget);
    expect(store.saved, hasLength(1), reason: '同 id 覆盖，不重复落盘');
  });

  testWidgets('prefs 不可用（未 mock）→ 默认皮肤兜底，页面正常渲染', (tester) async {
    // 不调 SharedPreferences.setMockInitialValues → getInstance 抛
    // MissingPluginException → catchError 兜底（catalog 默认皮肤）。
    final store = FakeEndgameStore();
    await pumpPage(tester, _record(), store);

    expect(find.byType(ChessBoard), findsNWidgets(5),
        reason: '主棋盘 + 4 档快照正常渲染');
  });

  testWidgets('prefs 指定皮肤 id → 页面按该 id 解析皮肤（跟随当前选中）', (tester) async {
    SharedPreferences.setMockInitialValues({'chess_skin_id': '2'});
    final store = FakeEndgameStore();
    await pumpPage(tester, _record(), store);
    await tester.pumpAndSettle();

    // 皮肤 id '2' 与默认 '1' 解析出的实例不同（byId 按 catalog 注册表返回）。
    final expected = ChessSkinBundle.byId('2');
    final board = tester.widget<ChessBoard>(
      find.byType(ChessBoard).first,
    );
    expect(identical(board.skin, expected), isTrue,
        reason: '回放页皮肤 = prefs 指定 id 的解析结果');
  });
}
