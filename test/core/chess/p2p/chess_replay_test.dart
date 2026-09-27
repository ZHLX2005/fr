// test/core/chess/p2p/chess_replay_test.dart
//
// 对局回放（复盘）widget 测试 —— Fake RoomHandle/transport（与
// chess_room_page_test.dart 同款设计：真实 RoomHandle + MockClient 不联网，
// 手动 pushSnapshot 驱动快照）。
//
// 覆盖：
//   · 终局 → 点"复盘" → 回放条出现 + 棋盘显示终局局面 + 状态条"回放中"
//   · 单步后退 < → 棋盘回到上一手之前（上一步高亮跟随）
//   · |< 回到开局 → 初始局面 32 子 + 边界按钮禁用 + 无上一步高亮
//   · 自动播放 ▶ → 定时器推进 → 到终局自动停（播放键复位）
//   · 拖动进度条 → 跳步
//   · 回放中输入禁用：tap 不选中 / 不发 MOVE
//   · 退出回放 → 终局覆盖层回来
//   · RESET 后新终局再复盘 → 棋谱为新局（无上局残留）
//   · 回放中收到 RESET 快照（host 重开）→ 自动退出回放
//   · 零走法终局（立刻投降）→ 复盘按钮不显示

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_room_page.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record.dart';
import 'package:xiaodouzi_fr/core/chess/replay/chess_game_record_store.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_replay_bar.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 真实 RelayV3Transport + MockClient（不联网），记录 applyAction 调用。
class FakeTransport extends RelayV3Transport {
  FakeTransport({required super.deviceId})
    : super(
        relayUrl: 'http://fake',
        alias: 'me',
        httpClient: MockClient(_handler),
      );

  static Future<http.Response> _handler(http.Request req) async {
    final code = req.url.pathSegments.isNotEmpty
        ? req.url.pathSegments.last
        : '000000';
    return http.Response(
      jsonEncode({
        'data': {'ws_url': 'ws://fake/ws3/$code', 'snapshot': _snapJson(code)},
      }),
      200,
    );
  }

  static Map<String, dynamic> _snapJson(String code) => {
    'room_code': code,
    'script_hash': '',
    'script_src': '',
    'context': {'n': 0},
    'state': '',
    'version': 1,
    'created_at': '2026-07-25T10:00:00Z',
    'updated_at': '2026-07-25T10:00:00Z',
    'history': <dynamic>[],
  };
}

/// 记录一次 applyAction 调用。
class FakeActionCall {
  final String type;
  FakeActionCall(this.type);
}

/// Fake RoomHandle —— 复用真实 RoomHandle（testCreate，不连 WS）。
/// 覆写 snapshots 指向自持广播流（手动 pushSnapshot 模拟 WS 广播）；
/// 覆写 applyAction 只记录调用（回放测试不需要模拟服务端 MOVE 落盘）。
class FakeRoomHandle extends RoomHandle {
  final List<FakeActionCall> actionCalls = [];
  bool left = false;

  final StreamController<Snapshot> _fakeSnapshots =
      StreamController<Snapshot>.broadcast();

  FakeRoomHandle({
    required FakeTransport transport,
    required String code,
    Snapshot? initial,
  }) : super.testCreate(
         transport: transport,
         code: code,
         wsUrl: 'ws://fake/ws3/$code',
         initial: initial,
       );

  @override
  Stream<Snapshot> get snapshots => _fakeSnapshots.stream;

  /// 手动推送快照（模拟服务端 WS 广播）。
  void pushSnapshot(Snapshot snap) {
    latest = snap;
    if (!_fakeSnapshots.isClosed) {
      _fakeSnapshots.add(snap);
    }
  }

  @override
  Future<Snapshot> applyAction({
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    String? sourceDeviceId,
  }) async {
    actionCalls.add(FakeActionCall(type));
    return latest!;
  }

  @override
  Future<void> leave() async {
    left = true;
  }
}

/// 内存版整局记录 store —— testWidgets 的 FakeAsync zone 里 await 真实
/// 文件 IO 会挂死（同 chess_game_record_list_page_test 的 _FakeStore 理由）。
/// 语义对齐磁盘：同 id 覆写（同毫秒 id 冲突时表现为合并，测试只断言
/// 「auto ≤ 窗口 + 最新局在场」这类对合并鲁棒的不变量）。
class _FakeRecordStore extends ChessGameRecordStore {
  _FakeRecordStore() : super(isWeb: false);

  final List<ChessGameRecord> records = [];

  @override
  Future<List<ChessGameRecord>> loadAll() async =>
      List.of(records)..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  @override
  Future<void> save(ChessGameRecord r) async {
    records.removeWhere((e) => e.id == r.id);
    records.add(r);
  }

  @override
  Future<void> delete(String id) async =>
      records.removeWhere((e) => e.id == id);
}

/// 生成一份快照（同 chess_room_page_test 的 makeSnapshot）。
Snapshot makeSnapshot({
  required String code,
  required String fen,
  required String status,
  String state = 'playing',
  String? hostId,
  String? guestId,
  String? winner,
  List<dynamic> moves = const [],
}) {
  return Snapshot(
    roomCode: code,
    scriptHash: 'fake',
    scriptSrc: null,
    context: {
      'host_id': hostId,
      'guest_id': guestId,
      'players': <String, dynamic>{
        ?hostId: 'host',
        ?guestId: 'guest',
      },
      'fen': fen,
      'moves': moves,
      'draw_offers': <String, dynamic>{},
      'status': status,
      'winner': ?winner,
    },
    state: state,
    version: 1,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    history: const [],
  );
}

/// host = 'd-host'（白方），guest = 'd-guest'。
FakeRoomHandle makeHandle({required bool host}) {
  final transport = FakeTransport(deviceId: host ? 'd-host' : 'd-guest');
  return FakeRoomHandle(
    transport: transport,
    code: '999999',
    initial: makeSnapshot(
      code: '999999',
      fen: kStartingFen,
      status: 'playing',
      hostId: 'd-host',
      guestId: 'd-guest',
    ),
  );
}

void main() {
  setUp(() => ChessSkinBundle.resetForTest());

  /// 用真实引擎逐手重演棋谱 → 终局 FEN（与页面回放构建同源：
  /// UCI 与引擎合法走法匹配 → applyMove）。
  String finalFenOf(List<String> ucis) {
    const engine = ChessEngine();
    var state = BoardState.initial();
    for (final uci in ucis) {
      final raw = Move.fromUci(uci);
      final m = engine
          .generateLegalMoves(state)
          .firstWhere(
            (m) =>
                m.from == raw.from &&
                m.to == raw.to &&
                m.promotion == raw.promotion,
          );
      state = applyMove(state, m).nextState;
    }
    return FenCodec.toFen(state);
  }

  /// 测试用短对局：1.e4 e5 2.Nf3 Nc6（4 手，均为合法走法）。
  const gameLine = ['e2e4', 'e7e5', 'g1f3', 'b8c6'];

  /// 推一份"已结束 + 完整棋谱"的快照（checkmate，host 赢）。
  void pushEndedGame(FakeRoomHandle handle, List<String> ucis) {
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: finalFenOf(ucis),
        status: 'checkmate',
        state: 'ended',
        hostId: 'd-host',
        guestId: 'd-guest',
        winner: 'd-host',
        moves: [
          for (var i = 0; i < ucis.length; i++)
            {'uci': ucis[i], 'by': i.isEven ? 'd-host' : 'd-guest', 'ts': i},
        ],
      ),
    );
  }

  /// host widget 包装（600x600 可点棋盘；store 注入测自动保存）。
  Widget host(FakeRoomHandle handle, {_FakeRecordStore? store}) {
    ChessSkinBundle.registerHardcoded();
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 600,
            child: ChessRoomPage(handle: handle, gameRecordStore: store),
          ),
        ),
      ),
    );
  }

  /// 当前棋盘 widget 的局面（回放 / 实况共用这一个渲染入口）。
  BoardState boardState(WidgetTester tester) =>
      tester.widget<ChessBoard>(find.byType(ChessBoard)).state;

  /// 进入终局 + 进入回放（复用：终局快照 → pump ×3 → 点复盘 → pump）。
  Future<void> enterReplay(WidgetTester tester, FakeRoomHandle handle) async {
    pushEndedGame(handle, gameLine);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '复盘'));
    await tester.pump();
  }

  testWidgets('终局 → 点复盘 → 回放条出现 + 棋盘显示终局局面（从终局开始）', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await enterReplay(tester, handle);

    // 回放条出现，步数标签 "4 / 4"（从终局开始），状态条提示回放中。
    expect(find.byType(ChessReplayBar), findsOneWidget);
    expect(find.text('4 / 4'), findsOneWidget);
    // 我方状态条 subtitle = 执子色 · 回放中（host 默认执白）。
    expect(find.text('执白 · 回放中'), findsOneWidget);
    // 终局覆盖层隐藏（退出回放才回来）。
    expect(find.text('将杀'), findsNothing);
    // 棋盘 = 终局局面：e4 白兵 / f3 白马 / c6 黑马。
    final st = boardState(tester);
    expect(st.pieceTypeAt(squareToIndex('e4')), PieceType.pawn);
    expect(st.pieceColorAt(squareToIndex('e4')), PieceColor.white);
    expect(st.pieceTypeAt(squareToIndex('f3')), PieceType.knight);
    expect(st.pieceTypeAt(squareToIndex('c6')), PieceType.knight);
  });

  testWidgets('回放：单步后退 < → 棋盘回到上一手之前 + 上一步高亮跟随', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await enterReplay(tester, handle);

    // 后退一步（4 → 3）：c6 黑马回到 b8，f3 白马仍在。
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(find.text('3 / 4'), findsOneWidget);
    var st = boardState(tester);
    expect(st.isEmpty(squareToIndex('c6')), isTrue, reason: '第 4 手 b8c6 已撤销');
    expect(st.pieceTypeAt(squareToIndex('f3')), PieceType.knight);
    expect(st.pieceTypeAt(squareToIndex('b8')), PieceType.knight);
    // 上一步高亮 = 当前步的前一手（index 3 → 第 3 手 g1f3）。
    final lm = tester.widget<ChessBoard>(find.byType(ChessBoard)).lastMove;
    expect(lm, isNotNull);
    expect(lm!.from, squareToIndex('g1'));
    expect(lm.to, squareToIndex('f3'));
  });

  testWidgets('回放：|< 回到开局 → 初始局面 32 子 + 边界按钮禁用 + 无高亮', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await enterReplay(tester, handle);

    await tester.tap(find.byIcon(Icons.first_page));
    await tester.pump();
    expect(find.text('0 / 4'), findsOneWidget);
    // 初始局面：32 子 + e2 有兵。
    final st = boardState(tester);
    expect(st.cells.whereType<int>().length, 32);
    expect(st.pieceTypeAt(squareToIndex('e2')), PieceType.pawn);
    // 边界禁用：|< 和 < 置灰（onPressed == null）。
    final toStartBtn = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.first_page),
    );
    final backBtn = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.chevron_left),
    );
    expect(toStartBtn.onPressed, isNull);
    expect(backBtn.onPressed, isNull);
    // 初始局面无上一步高亮。
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).lastMove,
      isNull,
    );
  });

  testWidgets('回放：自动播放 ▶ → 定时器推进 → 到终局自动停（播放键复位）', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await enterReplay(tester, handle);

    // 回到开局后按 ▶：从 0 开始自动播放（每 800ms 一手）。
    await tester.tap(find.byIcon(Icons.first_page));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.text('0 / 4'), findsOneWidget);

    // 第 1 手 e2e4：e2 空、e4 白兵。
    await tester.pump(const Duration(milliseconds: 900));
    var st = boardState(tester);
    expect(st.isEmpty(squareToIndex('e2')), isTrue);
    expect(st.pieceTypeAt(squareToIndex('e4')), PieceType.pawn);
    expect(find.text('1 / 4'), findsOneWidget);

    // 剩余 3 手全部走完 → 到终局自动停播（⏸ 复位 ▶）。
    await tester.pump(const Duration(milliseconds: 900) * 3);
    await tester.pump();
    st = boardState(tester);
    expect(st.pieceTypeAt(squareToIndex('c6')), PieceType.knight, reason: '自动播放推进到终局');
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget, reason: '到终局自动停播');
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('回放：拖动进度条 → 跳步', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await enterReplay(tester, handle);

    // 从终局（4 / 4）把进度条拖到最左 → 回到开局（e2 兵还在）。
    final rect = tester.getRect(find.byType(Slider));
    await tester.dragFrom(rect.center, Offset(-rect.width, 0));
    await tester.pumpAndSettle();
    final st = boardState(tester);
    expect(st.pieceTypeAt(squareToIndex('e2')), PieceType.pawn,
        reason: '拖到最左 = 回到初始局面');
  });

  testWidgets('回放中输入禁用：tap 棋盘不选中 / 不发 MOVE（只读复盘）', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await enterReplay(tester, handle);

    // 回放中点任意格：无选中高亮、无 MOVE action。
    final detectors = find.byType(GestureDetector);
    expect(detectors, findsWidgets);
    await tester.tap(detectors.at(squareToIndex('e2')));
    await tester.pump();
    await tester.tap(detectors.at(squareToIndex('e4')));
    await tester.pump();

    expect(handle.actionCalls, isEmpty, reason: '回放中不得发任何 action');
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).selectedSquare,
      isNull,
      reason: '回放中 tap 不得产生选中',
    );
    // 输入回调整体断开（棋盘只读）。
    expect(
      tester.widget<ChessBoard>(find.byType(ChessBoard)).onSquareTap,
      isNull,
      reason: '回放中 tap 回调应断开',
    );
  });

  testWidgets('退出回放 → 终局覆盖层回来', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await enterReplay(tester, handle);
    expect(find.byType(ChessReplayBar), findsOneWidget);

    await tester.tap(find.text('退出回放'));
    await tester.pump();

    // 回放条消失，终局覆盖层（将杀 / 再来一局 / 复盘 / 返回）回来。
    expect(find.byType(ChessReplayBar), findsNothing);
    expect(find.text('将杀'), findsOneWidget);
    expect(find.text('你赢了'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '复盘'), findsOneWidget);
    expect(find.text('回放中'), findsNothing);
    // 可再次进入回放（状态干净）。
    await tester.tap(find.widgetWithText(OutlinedButton, '复盘'));
    await tester.pump();
    expect(find.text('4 / 4'), findsOneWidget);
  });

  testWidgets('RESET 后新终局再复盘 → 棋谱为新局（无上局残留）', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 第 1 局：4 手终局 → 复盘一次。
    await enterReplay(tester, handle);
    expect(find.text('4 / 4'), findsOneWidget);
    await tester.tap(find.text('退出回放'));
    await tester.pump();

    // host 再来一局（RESET）→ 服务端清棋谱回 playing。
    await tester.tap(find.widgetWithText(FilledButton, '再来一局'));
    await tester.pump();
    expect(handle.actionCalls.last.type, 'RESET');
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        state: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
      ),
    );
    await tester.pump();
    await tester.pump();

    // 第 2 局：2 手（d2d4 d7d5）终局 → 再复盘：步数 / 局面都是新局的。
    pushEndedGame(handle, const ['d2d4', 'd7d5']);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '复盘'));
    await tester.pump();

    expect(find.text('2 / 2'), findsOneWidget, reason: 'RESET 后棋谱为新局');
    var st = boardState(tester);
    expect(st.pieceTypeAt(squareToIndex('d4')), PieceType.pawn);
    expect(st.pieceColorAt(squareToIndex('d4')), PieceColor.white);
    expect(st.pieceColorAt(squareToIndex('d5')), PieceColor.black);

    // |< 回到开局 → 仍是标准 32 子初始局面。
    await tester.tap(find.byIcon(Icons.first_page));
    await tester.pump();
    st = boardState(tester);
    expect(st.cells.whereType<int>().length, 32);
    expect(st.pieceTypeAt(squareToIndex('e2')), PieceType.pawn);
  });

  testWidgets('回放中收到 RESET 快照（host 重开）→ 自动退出回放回实况', (tester) async {
    // guest 在复盘，host 点了再来一局 → 快照回 playing。
    final handle = makeHandle(host: false);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    pushEndedGame(handle, gameLine);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, '复盘'));
    await tester.pump();
    expect(find.byType(ChessReplayBar), findsOneWidget);

    // host RESET → 新 playing 快照：回放必须自动退出（复盘对象已失效）。
    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'playing',
        state: 'playing',
        hostId: 'd-host',
        guestId: 'd-guest',
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ChessReplayBar), findsNothing, reason: 'RESET 后自动退出回放');
    expect(find.text('将杀'), findsNothing);
    expect(find.text('回放中'), findsNothing);
    // 棋盘回到实况（新对局起始局面）。
    expect(boardState(tester).cells.whereType<int>().length, 32);
  });

  testWidgets('零走法终局（立刻投降）→ 复盘按钮不显示', (tester) async {
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'resigned',
        state: 'ended',
        hostId: 'd-host',
        guestId: 'd-guest',
        winner: 'd-guest',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('认输'), findsOneWidget);
    expect(find.text('复盘'), findsNothing, reason: '无走法对局没有回放内容');
    expect(find.widgetWithText(OutlinedButton, '返回'), findsOneWidget);
  });

  testWidgets('终局 → 整局自动入库（auto 标记 + 静默，无重复落盘）', (tester) async {
    final store = _FakeRecordStore();
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle, store: store));
    await tester.pump();

    // 终局快照到达（无需进复盘）→ 自动入库。
    pushEndedGame(handle, gameLine);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(store.records, hasLength(1), reason: '终局即自动保存，无需手动');
    final r = store.records.single;
    expect(r.auto, isTrue);
    expect(r.roomCode, '999999');
    expect(r.status, 'checkmate');
    expect(r.uciMoves, gameLine);
    // 完全静默：不弹任何 SnackBar。
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('自动保存'), findsNothing);

    // 同一终局快照重推（连接抖动场景）→ 终局覆盖层已显示过 → 不再触发，不重复入库。
    pushEndedGame(handle, gameLine);
    await tester.pump();
    await tester.pump();
    expect(store.records, hasLength(1), reason: '重复终局快照不重复落盘');
  });

  testWidgets('零走法终局（立刻投降）→ 不自动入库', (tester) async {
    final store = _FakeRecordStore();
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle, store: store));
    await tester.pump();

    handle.pushSnapshot(
      makeSnapshot(
        code: '999999',
        fen: kStartingFen,
        status: 'resigned',
        state: 'ended',
        hostId: 'd-host',
        guestId: 'd-guest',
        winner: 'd-guest',
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(store.records, isEmpty, reason: '无可回放内容 → 不入库');
  });

  testWidgets('自动入库后手动保存同一局 → 转正（auto→false）', (tester) async {
    final store = _FakeRecordStore();
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle, store: store));
    await tester.pump();

    // 终局 → 自动入库（auto=true）。
    pushEndedGame(handle, gameLine);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(store.records.single.auto, isTrue);

    // 进复盘点「保存整局到对局库」→ 命中同内容自动条目 → 转正。
    await tester.tap(find.widgetWithText(OutlinedButton, '复盘'));
    await tester.pump();
    await tester.tap(find.byTooltip('保存整局到对局库'));
    await tester.pump();
    await tester.pump();

    expect(store.records, hasLength(1), reason: '转正是同一条目的原地改写');
    expect(store.records.single.auto, isFalse, reason: '手动保存后不再被滚动清理');
    expect(find.text('已保存整局（4 手）到对局回放库'), findsOneWidget);

    // ScaffoldMessenger 是队列制（同时只演一条）：喂足假时钟让第一条走完
    // 入场（计时器在入场完成后才启动）→ 4s 停留 → 退场，清空队列。
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已保存整局（4 手）到对局回放库'), findsNothing);

    // 再点一次 → 已是手动条目 → 提示无需重复保存。
    await tester.tap(find.byTooltip('保存整局到对局库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('该局已在回放库中，无需重复保存'), findsOneWidget);
    expect(store.records.single.auto, isFalse);
  });

  testWidgets('连打四局 → 自动条目滚动只留最近三局', (tester) async {
    final store = _FakeRecordStore();
    final handle = makeHandle(host: true);
    await tester.pumpWidget(host(handle, store: store));
    await tester.pump();

    // 第 1 局：直接推终局快照 → 自动入库。
    pushEndedGame(handle, const ['e2e4', 'e7e5', 'g1f3', 'b8c6']);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 之后每局：host 再来一局（RESET）→ 回 playing → 推下一局终局。
    Future<void> nextGame(List<String> ucis) async {
      await tester.tap(find.widgetWithText(FilledButton, '再来一局'));
      await tester.pump();
      handle.pushSnapshot(
        makeSnapshot(
          code: '999999',
          fen: kStartingFen,
          status: 'playing',
          state: 'playing',
          hostId: 'd-host',
          guestId: 'd-guest',
        ),
      );
      await tester.pump();
      await tester.pump();
      pushEndedGame(handle, ucis);
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    await nextGame(const ['d2d4', 'd7d5']);
    await nextGame(const ['c2c4', 'c7c5', 'b1c3']);
    await nextGame(const ['g1f3', 'g8f6']);

    // 不变量（对同毫秒 id 合并鲁棒）：auto 条目不超过窗口数，且最新一局在场。
    final autos = store.records.where((r) => r.auto).toList();
    expect(autos.length, lessThanOrEqualTo(kChessGameAutoKeep));
    expect(
      autos.any((r) => r.uciMoves.join(',') == 'g1f3,g8f6'),
      isTrue,
      reason: '最新一局必被保留',
    );
  });
}
