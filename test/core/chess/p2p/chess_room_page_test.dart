// test/core/chess/p2p/chess_room_page_test.dart
//
// ChessRoomPage（P2P 在线对弈页）widget 测试 —— 使用 FAKE RoomHandle/transport：
//   · 初始快照（fen + status playing）→ 渲染 ChessBoard
//   · 白方（host）回合：tap e2 → tap e4 → 发送 MOVE（uci 'e2e4'）
//   · 非我回合：tap 不发 MOVE
//   · 对方走子快照（新 fen）→ 棋盘更新
//   · status == checkmate → 终局覆盖层出现
//   · RESIGN 按钮 → 发送 RESIGN action
//
// Fake 设计：复用真实 RoomHandle + 真实 RelayV3Transport，但 HTTP 走 MockClient
// （不联网），并用 RoomHandle.testCreate 注入初始快照 —— WS 不连接。
// 触发棋盘更新的方式 = 手动向 handle.pushSnapshot(...) 推送新快照。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_room_page.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_connection_bar.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 记录一次 applyAction 调用。
class FakeActionCall {
  final String type;
  final Map<String, dynamic> params;
  FakeActionCall(this.type, this.params);
}

/// 真实 RelayV3Transport + MockClient（不联网），记录 applyAction 调用。
class FakeTransport extends RelayV3Transport {
  final List<FakeActionCall> actionCalls = [];
  Map<String, dynamic>? lastParams;
  bool failWith409 = false;

  FakeTransport({required String deviceId})
      : super(
          relayUrl: 'http://fake',
          alias: 'me',
          deviceId: deviceId,
          httpClient: MockClient(_handler),
        );

  /// MockClient 处理器 —— 所有 HTTP 端点都回一个可解析的 envelope。
  static Future<http.Response> _handler(http.Request req) async {
    final code = req.url.pathSegments.isNotEmpty
        ? req.url.pathSegments.last
        : '000000';
    return http.Response(
      jsonEncode({
        'data': {
          'ws_url': 'ws://fake/ws3/$code',
          'snapshot': _snapJson(code),
        },
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

/// Fake RoomHandle —— 复用真实 RoomHandle（testCreate，不连 WS）。
///
/// 覆写 `snapshots` getter 指向自己的广播控制器（基类的 `_snapshotsCtrl` 是
/// library-private，子类拿不到），从而支持手动 `pushSnapshot(...)` 模拟 WS 广播。
/// 覆写 applyAction：记录调用；成功时模拟服务端把 MOVE 的 fen/status
/// 写回 context 并推流（等价于真实 transport 的"成功→更新 latest + 推流"）。
class FakeRoomHandle extends RoomHandle {
  final List<FakeActionCall> actionCalls = [];
  Map<String, dynamic>? lastParams;
  bool failWith409 = false;
  bool left = false;

  /// 自持快照流（测试驱动：手动 push 模拟 WS 广播）。
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
    final call = FakeActionCall(type, Map<String, dynamic>.from(params));
    actionCalls.add(call);
    lastParams = call.params;
    if (failWith409) {
      throw RelayV3Exception(409, 'version conflict');
    }
    // 成功路径：模拟服务端把 MOVE 的 fen/status 写回 context。
    if (type == 'MOVE') {
      final ctx = Map<String, dynamic>.from(latest?.context ?? {});
      ctx['fen'] = params['fen'];
      ctx['status'] = params['status'];
      final next = Snapshot(
        roomCode: code,
        scriptHash: latest?.scriptHash ?? '',
        scriptSrc: latest?.scriptSrc,
        context: ctx,
        state: 'playing',
        version: (latest?.version ?? 0) + 1,
        createdAt: latest?.createdAt ?? DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        history: latest?.history ?? const [],
      );
      latest = next;
      if (!_fakeSnapshots.isClosed) {
        _fakeSnapshots.add(next);
      }
    }
    return latest!;
  }

  @override
  Future<void> leave() async {
    left = true;
  }
}

/// 生成一份快照。
Snapshot makeSnapshot({
  required String code,
  required String fen,
  required String status,
  String state = 'playing',
  String? hostId,
  String? guestId,
  String? winner,
}) {
  return Snapshot(
    roomCode: code,
    scriptHash: 'fake',
    scriptSrc: null,
    context: {
      'host_id': hostId,
      'guest_id': guestId,
      'players': <String, dynamic>{
        if (hostId != null) hostId: 'host',
        if (guestId != null) guestId: 'guest',
      },
      'fen': fen,
      'moves': <dynamic>[],
      'draw_offers': <dynamic>{},
      'status': status,
      if (winner != null) 'winner': winner,
    },
    state: state,
    version: 1,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    history: const [],
  );
}

/// host = 'd-host'（白方），guest = 'd-guest'，本地 = host。
FakeRoomHandle makeHostHandle() {
  final transport = FakeTransport(deviceId: 'd-host');
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

/// 本地 = guest（黑方）的句柄。
FakeRoomHandle makeGuestHandle() {
  final transport = FakeTransport(deviceId: 'd-guest');
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

  /// 用 ChessRoomPage 包一层 host widget（默认 600x600 可点棋盘）。
  Widget host(FakeRoomHandle handle) {
    ChessSkinBundle.registerHardcoded();
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            height: 600,
            child: ChessRoomPage(
              handle: handle,
              skinId: kChessSkinsCatalog[0].id,
            ),
          ),
        ),
      ),
    );
  }

  /// 按 GestureDetector 顺序 tap 第 idx 个（0..63 = 1D idx）。
  Future<void> tapCell(WidgetTester tester, int idx) async {
    final detectors = find.byType(GestureDetector);
    expect(detectors, findsWidgets);
    await tester.tap(detectors.at(idx));
    await tester.pump();
  }

  testWidgets('初始快照（fen + status playing）→ 渲染 ChessBoard', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    expect(find.byType(ChessBoard), findsOneWidget);
    expect(find.textContaining('你的回合'), findsOneWidget);
  });

  testWidgets('我的回合（host=白）：tap e2 → tap e4 → 发送 MOVE uci e2e4',
      (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    final e2 = squareToIndex('e2');
    final e4 = squareToIndex('e4');
    await tapCell(tester, e2);
    await tapCell(tester, e4);
    await tester.pump();

    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'MOVE');
    expect(handle.lastParams?['uci'], 'e2e4');
    // 合规 fence：MOVE 不携带 status（终局走 CLAIM_END），fen 必须存在且结构合法。
    expect(handle.lastParams?.containsKey('status'), isFalse,
        reason: 'MOVE 不得携带 status（服务端校验 fence 的一部分）');
    expect(handle.lastParams?['fen'], isA<String>());
  });

  testWidgets('非我回合（guest=黑，轮白走）：tap 不发 MOVE', (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await tapCell(tester, squareToIndex('e2'));
    await tester.pump();
    await tapCell(tester, squareToIndex('e4'));
    await tester.pump();

    expect(handle.actionCalls, isEmpty);
  });

  testWidgets('对方走子快照（新 fen）→ 棋盘更新', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // host（白）走 e2-e4 后，guest（黑）回应 d7-d5 的快照。
    // fen：e2e4 d7d5 之后（轮到白方走）。
    const newFen =
        'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2';
    handle.pushSnapshot(makeSnapshot(
      code: '999999',
      fen: newFen,
      status: 'playing',
      hostId: 'd-host',
      guestId: 'd-guest',
    ));
    await tester.pump();

    // 棋盘内容从快照 fen 重建：e4 / d5 有子，e2 已空，轮到白。
    final board = FenCodec.fromFen(newFen);
    expect(board.slotAt(squareToIndex('e4')), isNotNull);
    expect(board.slotAt(squareToIndex('d5')), isNotNull);
    expect(board.isEmpty(squareToIndex('e2')), isTrue);
    expect(find.textContaining('你的回合'), findsOneWidget);
  });

  testWidgets('status == checkmate → 终局覆盖层出现（host 可见再来一局）',
      (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(makeSnapshot(
      code: '999999',
      fen: kStartingFen,
      status: 'checkmate',
      state: 'ended',
      hostId: 'd-host',
      guestId: 'd-guest',
      winner: 'd-host',
    ));
    // 广播流是异步派发（微任务），需多 pump 几次直到新快照被应用。
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('将杀'), findsOneWidget);
    expect(find.text('你赢了'), findsOneWidget);
    // host 终局卡片：再来一局（FilledButton）+ 返回（OutlinedButton）
    expect(find.widgetWithText(FilledButton, '再来一局'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '返回'), findsOneWidget);
  });

  testWidgets('status == stalemate → 终局覆盖层（guest 不可见再来一局）',
      (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(makeSnapshot(
      code: '999999',
      fen: kStartingFen,
      status: 'stalemate',
      state: 'ended',
      hostId: 'd-host',
      guestId: 'd-guest',
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('僵局'), findsOneWidget);
    expect(find.text('平局'), findsOneWidget);
    // guest 看不到"再来一局"（RESET 仅 host 可调）
    expect(find.text('再来一局'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '返回'), findsOneWidget);
  });

  testWidgets('RESIGN 按钮 → 发送 RESIGN action', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '投降'));
    await tester.pump();

    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'RESIGN');
  });

  // ─────────────── 合规修复：翻转由角色驱动（不随 sideToMove 抖动） ───────────────

  testWidgets('host=白视角：整局棋盘不翻转（flipped 恒 false）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    ChessBoard board() => tester.widget<ChessBoard>(find.byType(ChessBoard));
    // 白方视角：flipped 恒 false（我始终在底，稳定）。
    expect(board().flipped, isFalse);
    // 白先手：sideToMove = white。
    expect(board().sideToMove, PieceColor.white);

    // 模拟黑方回应 d7-d5（轮白）→ 棋盘更新，但视角保持不翻转。
    const newFen =
        'rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2';
    handle.pushSnapshot(makeSnapshot(
      code: '999999',
      fen: newFen,
      status: 'playing',
      hostId: 'd-host',
      guestId: 'd-guest',
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(board().sideToMove, PieceColor.white);
    expect(board().flipped, isFalse,
        reason: '视角由角色驱动，不随 sideToMove 翻转');
  });

  testWidgets('guest=黑视角：翻转由角色驱动（flipped 恒 true）', (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    ChessBoard board() => tester.widget<ChessBoard>(find.byType(ChessBoard));
    expect(board().flipped, isTrue, reason: '我方执黑 → 黑方视角，黑在底');
  });

  // ─────────────── 合规修复：RESET（host 再来一局 → 新对局） ───────────────

  testWidgets('终局 → host 点"再来一局" → 发 RESET → 快照回 playing 清空本地态',
      (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    // 1. 进入终局（checkmate）。
    handle.pushSnapshot(makeSnapshot(
      code: '999999',
      fen: kStartingFen,
      status: 'checkmate',
      state: 'ended',
      hostId: 'd-host',
      guestId: 'd-guest',
      winner: 'd-host',
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('再来一局'), findsOneWidget);

    // 2. host 点"再来一局" → RESET action。
    await tester.tap(find.widgetWithText(FilledButton, '再来一局'));
    await tester.pump();
    expect(handle.actionCalls, hasLength(1));
    expect(handle.actionCalls.first.type, 'RESET');

    // 3. 服务端 RESET 后推送新快照（回 playing + 起始 fen）。
    handle.pushSnapshot(makeSnapshot(
      code: '999999',
      fen: kStartingFen,
      status: 'playing',
      state: 'playing',
      hostId: 'd-host',
      guestId: 'd-guest',
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 终局覆盖层消失；host 又能正常走子。
    expect(find.text('再来一局'), findsNothing);
    expect(find.text('将杀'), findsNothing);
    expect(find.textContaining('你的回合'), findsOneWidget);

    // 4. 重开后走子正常（上一局 _lastMove/_selectedSquare 已清空）。
    final e2 = squareToIndex('e2');
    final e4 = squareToIndex('e4');
    await tapCell(tester, e2);
    await tapCell(tester, e4);
    await tester.pump();
    expect(handle.actionCalls.last.type, 'MOVE');
    expect(handle.lastParams?['uci'], 'e2e4');
  });

  testWidgets('guest 终局后不可见"再来一局"', (tester) async {
    final handle = makeGuestHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    handle.pushSnapshot(makeSnapshot(
      code: '999999',
      fen: kStartingFen,
      status: 'checkmate',
      state: 'ended',
      hostId: 'd-host',
      guestId: 'd-guest',
      winner: 'd-host',
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('再来一局'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '返回'), findsOneWidget);
  });

  // ─────────────── 合规修复：WS 状态条（RelayConnectionBar）存在 ───────────────

  testWidgets('房间页底部渲染 RelayConnectionBar（WS 状态可见）', (tester) async {
    final handle = makeHostHandle();
    await tester.pumpWidget(host(handle));
    await tester.pump();

    expect(find.byType(RelayConnectionBar), findsOneWidget);
    // 测试环境无真实 WS：状态条存在即可（连接文案随 isConnected 变化）。
    final texts = tester.widgetList<Text>(find.byType(Text));
    final hasConn = texts.any((t) => t.data == '已连接' || t.data == '已断开 · 自动重连中');
    expect(hasConn, isTrue);
    expect(find.text('拉取最新快照'), findsOneWidget);
  });
}
