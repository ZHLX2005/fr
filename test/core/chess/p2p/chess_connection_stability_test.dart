// test/core/chess/p2p/chess_connection_stability_test.dart
//
// 国际象棋 P2P 连接稳定性五件套测试：
//   1. RoomHandle heartbeat —— 在 relay_v3_transport_test.dart 单测覆盖
//   2. ConnectionStatusBadge（AppBar leading）三态显示（已连接 / 重连中…）
//   3. 手动刷新按钮 + fetchSnapshot 的 UI 反馈（顶部进度条 + 按钮 spinner）
//   4. 游戏中瞬断 rejoin 稳定：close(0) → overlay 不 pop + 本地棋盘不丢
//      → 快照恢复 → overlay 消失 + 棋盘按新快照重建
//   5. 重入保护（5s grace + 稳定 deviceId）：
//      · 同 deviceId 重连（disconnected 清除、fen/moves 保留）→ 恢复对局
//      · 不同 deviceId 加入满员房 → rejected_join（409）语义（静态脚本守卫
//        + 客户端快照语义验证）
//
// Fake 模式与 chess_ready_gate_test.dart 同构：真实 RoomHandle.testCreate
// + 覆写 snapshots / closeEvents 流（手动 push 模拟 WS）+ 可控 fetchSnapshot。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_room_page.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_connection_status.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 真实 RelayV3Transport + MockClient（不联网）。
class FakeTransport extends RelayV3Transport {
  FakeTransport({required super.deviceId})
    : super(
        relayUrl: 'http://fake',
        alias: 'me',
        httpClient: MockClient((req) async => http.Response('{}', 200)),
      );
}

/// 可控 RoomHandle —— 支持手动推快照 / 推 close 事件 / 延迟 fetchSnapshot。
class StableFakeHandle extends RoomHandle {
  final List<(String, Map<String, dynamic>)> actionCalls = [];
  final StreamController<Snapshot> _snapCtrl =
      StreamController<Snapshot>.broadcast();
  final StreamController<WSCloseEvent> _closeCtrl =
      StreamController<WSCloseEvent>.broadcast();

  /// fetchSnapshot 调用计数（手动刷新 / 409 reconcile 触发时 +1）。
  int fetchCalls = 0;

  /// 控制 fetchSnapshot 何时完成的闸门（null → 立即完成）。
  Completer<Snapshot>? fetchGate;

  /// fetchSnapshot 抛 409（模拟服务端版本冲突后的再拉取失败路径可另测）。
  Object? fetchError;

  /// applyAction 是否模拟 409 版本冲突（触发页面 reconcile 路径）。
  bool failActionWith409 = false;

  /// fetchSnapshot 返回的快照（默认 = 当前 latest）。
  Snapshot Function()? fetchResult;

  StableFakeHandle({
    required super.transport,
    required super.code,
    super.initial,
  }) : super.testCreate(wsUrl: 'ws://fake/ws3/$code');

  @override
  Stream<Snapshot> get snapshots => _snapCtrl.stream;

  @override
  Stream<WSCloseEvent> get closeEvents => _closeCtrl.stream;

  void pushSnapshot(Snapshot snap) {
    latest = snap;
    if (!_snapCtrl.isClosed) _snapCtrl.add(snap);
  }

  void pushClose({required int code, String reason = ''}) {
    if (!_closeCtrl.isClosed) {
      _closeCtrl.add(WSCloseEvent(code: code, reason: reason));
    }
  }

  @override
  Future<Snapshot> fetchSnapshot() async {
    fetchCalls++;
    final gate = fetchGate;
    if (gate != null) {
      // 闸门放行时以 complete 的快照为 fetch 结果（模拟服务端返回）。
      final v = await gate.future;
      latest = v;
      if (!_snapCtrl.isClosed) _snapCtrl.add(v);
      return v;
    }
    final err = fetchError;
    if (err != null) throw err;
    final snap = fetchResult?.call() ?? latest!;
    latest = snap;
    if (!_snapCtrl.isClosed) _snapCtrl.add(snap);
    return snap;
  }

  @override
  Future<Snapshot> applyAction({
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    String? sourceDeviceId,
  }) async {
    actionCalls.add((type, Map<String, dynamic>.from(params)));
    if (failActionWith409) {
      throw RelayV3Exception(409, 'version conflict');
    }
    return latest!;
  }
}

/// 生成一份快照（playing / disconnected 可控）。
Snapshot makeSnap({
  required String fen,
  String state = 'playing',
  String status = 'playing',
  String hostId = 'd-host',
  String guestId = 'd-guest',
  Map<String, dynamic>? disconnected,
  List<dynamic> moves = const [],
}) {
  final ctx = <String, dynamic>{
    'host_id': hostId,
    'guest_id': guestId,
    'players': <String, dynamic>{
      if (hostId.isNotEmpty) hostId: 'host',
      if (guestId.isNotEmpty) guestId: 'guest',
    },
    'fen': fen,
    'moves': moves,
    'status': status,
  };
  if (disconnected != null) ctx['disconnected'] = disconnected;
  return Snapshot(
    roomCode: '999999',
    scriptHash: 'fake',
    scriptSrc: null,
    context: ctx,
    state: state,
    version: 1,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    history: const [],
  );
}

StableFakeHandle makeHostHandle({Snapshot? initial}) {
  return StableFakeHandle(
    transport: FakeTransport(deviceId: 'd-host'),
    code: '999999',
    initial: initial ??
        makeSnap(fen: kStartingFen, hostId: 'd-host', guestId: 'd-guest'),
  );
}

StableFakeHandle makeGuestHandle({Snapshot? initial}) {
  return StableFakeHandle(
    transport: FakeTransport(deviceId: 'd-guest'),
    code: '999999',
    initial: initial ??
        makeSnap(fen: kStartingFen, hostId: 'd-host', guestId: 'd-guest'),
  );
}

Widget hostWidget(StableFakeHandle handle) {
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

/// 找 AppBar 上的"刷新快照"按钮。
Finder refreshButton() => find.byTooltip('刷新快照');

/// 1D index（白方视角）→ 格子中心全局坐标（几何推导，与实现解耦）。
///
/// 与 chess_room_page_test.dart 的 cellCenter 同一套几何：ChessBoard 自带
/// 16px 标签边距 + Center 居中 —— 按真实 rect 反推，不受 widget 树中
/// GestureDetector 数量 / 顺序变化影响（tapCell 按 detector 索引点会随
/// AppBar 改动漂移，这里全部走几何坐标 tapAt）。
Offset cellCenter(WidgetTester tester, int idx) {
  final rect = tester.getRect(find.byType(ChessBoard));
  final side = rect.width < rect.height ? rect.width : rect.height;
  const labelSpace = 16.0;
  final boardSize = side - labelSpace * 2;
  final cell = boardSize / kBoardCols;
  final gridLeft = rect.left + (rect.width - boardSize) / 2;
  final gridTop = rect.top + (rect.height - boardSize) / 2;
  final row = idx ~/ 8;
  final col = idx % 8;
  return Offset(
    gridLeft + labelSpace + col * cell + cell / 2,
    gridTop + labelSpace + row * cell + cell / 2,
  );
}

/// 几何坐标点击指定格。
Future<void> tapCell(WidgetTester tester, int idx) async {
  await tester.tapAt(cellCenter(tester, idx));
  await tester.pump();
}

void main() {
  setUp(() => ChessSkinBundle.resetForTest());

  group('Feature 2：ConnectionStatusBadge（AppBar 状态徽标）', () {
    testWidgets('初始（已连接）→ 绿点 + "已连接"', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      expect(find.byType(ChessConnectionStatusBadge), findsOneWidget);
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('重连中…'), findsNothing);
    });

    testWidgets('close(0) → 徽标变"重连中…"（橙态 + spinner，不 pop）', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      handle.pushClose(code: 0);
      await tester.pump();
      await tester.pump();

      expect(find.text('重连中…'), findsOneWidget);
      expect(find.text('已连接'), findsNothing);
      // 页面不 pop：棋盘仍在。
      expect(find.byType(ChessBoard), findsOneWidget);
    });

    testWidgets('快照恢复 → 徽标回"已连接"', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      handle.pushClose(code: 0);
      await tester.pump();
      await tester.pump();
      expect(find.text('重连中…'), findsOneWidget);

      // 任意新快照到达 → WS 恢复。
      handle.pushSnapshot(makeSnap(fen: kStartingFen));
      await tester.pump();
      await tester.pump();

      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('重连中…'), findsNothing);
    });

    testWidgets('被踢（4403 终端码）→ 徽标也进重连态但不 pop（等待用户操作）', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      handle.pushClose(code: 4403, reason: 'kicked');
      await tester.pump();
      await tester.pump();

      // 终端码走 snackbar 提示；徽标同步显示重连态（连接已断）。
      expect(find.textContaining('已被踢出房间'), findsOneWidget);
      expect(find.byType(ChessBoard), findsOneWidget, reason: '不自动 pop');
    });
  });

  group('Feature 3：手动刷新按钮 + fetchSnapshot UI 反馈', () {
    testWidgets('AppBar 有刷新按钮；点击 → fetchSnapshot + 顶部进度条 + 按钮 spinner', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      expect(refreshButton(), findsOneWidget);
      expect(handle.fetchCalls, 0);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // 用闸门挂住 fetchSnapshot → 断言"进行中"的 UI 反馈。
      final gate = Completer<Snapshot>();
      handle.fetchGate = gate;
      await tester.tap(refreshButton());
      await tester.pump();
      await tester.pump();

      expect(handle.fetchCalls, 1, reason: '点击刷新按钮触发 fetchSnapshot');
      expect(
        find.byType(LinearProgressIndicator),
        findsOneWidget,
        reason: '拉取中顶部显示进度条',
      );

      // 放行 → 进度条消失。
      gate.complete(makeSnap(fen: kStartingFen));
      await tester.pump();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(handle.fetchCalls, 1, reason: '无重复触发');
    });

    testWidgets('fetch 进行中按钮防双击（不重复 fetch）', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      final gate = Completer<Snapshot>();
      handle.fetchGate = gate;
      await tester.tap(refreshButton());
      await tester.pump();
      // 进行中再点 → onPressed 为 null / 早退，不重复发。
      await tester.tap(refreshButton(), warnIfMissed: false);
      await tester.pump();
      expect(handle.fetchCalls, 1);

      gate.complete(makeSnap(fen: kStartingFen));
      await tester.pump();
      await tester.pump();
    });

    testWidgets('fetch 失败 → snackbar 反馈 + 进度条复位', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      handle.fetchError = RelayV3Exception(500, 'boom');
      await tester.tap(refreshButton());
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('刷新失败'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('409 reconcile（走子版本冲突）→ 同样带 fetch 反馈', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      // 走子触发 409 → 页面走"拉最新快照 reconcile"，带 UI 反馈。
      handle.failActionWith409 = true;
      final gate = Completer<Snapshot>();
      handle.fetchGate = gate;

      // host（白）走 e2-e4。
      await tapCell(tester, squareToIndex('e2'));
      await tapCell(tester, squareToIndex('e4'));
      await tester.pump();

      expect(find.textContaining('状态已过期'), findsOneWidget, reason: '409 snackbar');
      expect(handle.fetchCalls, 1, reason: 'reconcile 走 fetchSnapshotWithFeedback');
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      gate.complete(makeSnap(
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1',
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1},
        ],
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      // 棋盘按 reconcile 快照重建（对手回合）。
      expect(find.textContaining('等待对方'), findsOneWidget);
    });
  });

  group('Feature 4：游戏中瞬断 rejoin 稳定（overlay + 状态不丢）', () {
    testWidgets('close(0) → overlay"连接断开" + 本地棋盘保留 → 快照恢复重建', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      // 1. 先走一手（本地乐观推进 e2-e4）。
      await tapCell(tester, squareToIndex('e2'));
      await tapCell(tester, squareToIndex('e4'));
      expect(handle.actionCalls.map((c) => c.$1), contains('MOVE'));
      // 乐观推进后 e4 有子。
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).state
            .slotAt(squareToIndex('e4')),
        isNotNull,
      );

      // 2. WS 瞬断 → overlay 出现，页面不 pop，棋盘保持乐观局面。
      handle.pushClose(code: 0);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('连接断开，正在重连'), findsOneWidget);
      expect(find.byType(ChessBoard), findsOneWidget, reason: '不退出页面');
      expect(
        tester.widget<ChessBoard>(find.byType(ChessBoard)).state
            .slotAt(squareToIndex('e4')),
        isNotNull,
        reason: '断线期间本地乐观局面不丢',
      );

      // 3. 重连成功 → 服务端权威快照（含我方 e2e4 echo）→ overlay 消失 + 重建。
      const reconciled =
          'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1';
      handle.pushSnapshot(makeSnap(
        fen: reconciled,
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1},
        ],
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('连接断开，正在重连'), findsNothing);
      final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
      expect(board.state.slotAt(squareToIndex('e4')), isNotNull);
      expect(board.state.isEmpty(squareToIndex('e2')), isTrue);
      expect(board.lastMove?.from, squareToIndex('e2'), reason: '高亮来自快照棋谱');
      // 轮到对方 → 输入被门挡（不误走子）。
      expect(find.textContaining('等待对方'), findsOneWidget);
    });

    testWidgets('重连快照版本回退防御：仍按快照整体重建（state 不回退场景由服务端保证）', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      handle.pushClose(code: 0);
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('连接断开，正在重连'), findsOneWidget);

      // 恢复快照（同一局面）→ overlay 消失。
      handle.pushSnapshot(makeSnap(fen: kStartingFen));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('连接断开，正在重连'), findsNothing);
      expect(find.byType(ChessBoard), findsOneWidget);
    });
  });

  group('Feature 5：重入保护（稳定 deviceId + 5s grace + 满员拒绝）', () {
    testWidgets('guest 掉线（disconnected[guest]）→ banner；同 deviceId 重连快照（fen/moves 保留）→ banner 清 + 棋局延续', (tester) async {
      // guest 已走 e7-e5（moves 1 条），随后掉线 → 服务端标 disconnected。
      const afterGuestMove =
          'rnbqkbnr/pppp1ppp/8/4p3/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final handle = makeGuestHandle(initial: makeSnap(
        fen: afterGuestMove,
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1},
          {'uci': 'e7e5', 'by': 'd-guest', 'ts': 2},
        ],
      ));
      await tester.pumpWidget(hostWidget(handle));
      await tester.pump();

      // guest 掉线快照：discovered 标记 + fen/moves 完整保留（房间不销毁）。
      handle.pushSnapshot(makeSnap(
        fen: afterGuestMove,
        disconnected: const {'d-guest': true},
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1},
          {'uci': 'e7e5', 'by': 'd-guest', 'ts': 2},
        ],
      ));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('你已掉线'), findsOneWidget);

      // 同 deviceId 重连（on_join 清 disconnected）→ 快照 fen/moves 原样保留
      // —— host 槽 / guest 槽 / 棋局进度都不重置。
      handle.pushSnapshot(makeSnap(
        fen: afterGuestMove,
        moves: const [
          {'uci': 'e2e4', 'by': 'd-host', 'ts': 1},
          {'uci': 'e7e5', 'by': 'd-guest', 'ts': 2},
        ],
      ));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('你已掉线'), findsNothing);
      final board = tester.widget<ChessBoard>(find.byType(ChessBoard));
      expect(
        board.state.slotAt(squareToIndex('e5')),
        isNotNull,
        reason: '重连后棋局延续（guest 的 e7e5 还在）',
      );
      expect(
        board.lastMove?.to,
        squareToIndex('e5'),
        reason: '上一步高亮保留（服务端棋谱未重置）',
      );
    });

    test('kChessScript 静态守卫：同 device_id 重连分支 + 满员拒绝分支存在', () {
      // 客户端无法嵌 Lua VM，这里对脚本做源级守卫（防回归误删）：
      // 1. on_join 首分支 = 同 device_id 早退（清 disconnected，不动槽位）。
      expect(
        kChessScript,
        contains('if c.players[p.device_id] ~= nil then'),
        reason: '同 device_id 重连 → 复用原槽位（5s grace 重入保护核心）',
      );
      expect(
        kChessScript,
        contains('c.disconnected[p.device_id] = nil'),
        reason: '重连清 disconnected 标记',
      );
      // 2. guest 槽已占 → rejected_join（满员 409 拒绝第三者）。
      expect(
        kChessScript,
        contains('c.rejected_join'),
        reason: '满员房第三者 → rejected_join → 服务端 409',
      );
      // 3. playing 内 guest 断线 → 房间保留等重连（不销毁）。
      expect(
        kChessScript,
        contains('c.disconnected[p.device_id] = true'),
        reason: 'guest 掉线 → disconnected 标记 + 房间 alive',
      );
    });

    test('rejected_join（满员 409）语义：joinRoom 抛 RelayV3Exception(409) → 客户端收到明确错误', () async {
      // 服务端对 rejected_join 房间回 409；客户端 transport.joinRoom 把非 200
      // 统一转 RelayV3Exception —— 这里验证该映射（满员提示走外层 snackbar）。
      final mock = MockClient((req) async {
        if (req.url.path.endsWith('/join')) {
          return http.Response(
            '{"code":409,"message":"join rejected: room full"}',
            409,
          );
        }
        return http.Response('{}', 200);
      });
      final t = RelayV3Transport(
        relayUrl: 'http://fake',
        alias: 'third-player',
        deviceId: 'd-other',
        httpClient: mock,
      );
      await expectLater(
        t.joinRoom(code: '999999'),
        throwsA(
          isA<RelayV3Exception>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.body, 'body', contains('room full')),
        ),
      );
    });
  });
}
