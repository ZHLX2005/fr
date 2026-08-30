// test/core/chess/p2p/chess_ready_gate_test.dart
//
// ChessRoomPage READY 门 + 断连等重连 专项测试（v2 协议升级）。
//
// 场景覆盖：
//   · lobby → 双方 ACK → ready → host DEAL → playing（READY 门全流程）
//   · playing → 快照 disconnected[myId] → 显示"你已掉线"banner + 棋盘冻结
//   · playing → 我方重连（同 device_id 快照清 disconnected）→ banner 消失
//   · playing → WS close code 0（瞬断）→ overlay "连接断开，正在重连…" 不 pop
//   · ready / lobby 快照 → 渲染准备卡片（"准备好了" / "开始游戏"）
//   · ChessRoom.readyMap / disconnectedPlayers / isHost / isGuest 静态读取
//
// Fake 复用真实 RoomHandle + 真实 RelayV3Transport（MockClient 不联网）+
// RoomHandle.testCreate 注入初始快照 —— 手动 pushSnapshot 模拟 WS 广播。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/chess/chess.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_net.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_room_page.dart';
import 'package:xiaodouzi_fr/core/chess/skins/chess_skin_meta.dart';
import 'package:xiaodouzi_fr/core/chess/widgets/chess_board.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 真实 RelayV3Transport + MockClient（不联网）。
class FakeTransport extends RelayV3Transport {
  FakeTransport({required String deviceId})
    : super(
        relayUrl: 'http://fake',
        alias: 'me',
        deviceId: deviceId,
        httpClient: MockClient((req) async => http.Response('{}', 200)),
      );
}

/// Fake RoomHandle —— RoomHandle.testCreate（不连 WS），手动推快照。
class FakeReadyHandle extends RoomHandle {
  final List<(String, Map<String, dynamic>)> actionCalls = [];
  final StreamController<Snapshot> _ctrl =
      StreamController<Snapshot>.broadcast();
  final StreamController<WSCloseEvent> _closeCtrl =
      StreamController<WSCloseEvent>.broadcast();

  FakeReadyHandle({
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
  Stream<Snapshot> get snapshots => _ctrl.stream;

  @override
  Stream<WSCloseEvent> get closeEvents => _closeCtrl.stream;

  void pushSnapshot(Snapshot snap) {
    latest = snap;
    if (!_ctrl.isClosed) _ctrl.add(snap);
  }

  /// 手动推送 WS 关闭事件（code=0 瞬断 / 4403 被踢等）。
  void pushClose({required int code, String reason = ''}) {
    if (!_closeCtrl.isClosed) _closeCtrl.add(WSCloseEvent(code: code, reason: reason));
  }

  @override
  Future<Snapshot> applyAction({
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    String? sourceDeviceId,
  }) async {
    actionCalls.add((type, Map<String, dynamic>.from(params)));
    return latest!;
  }
}

/// 生成一份快照（lobby / ready / playing 均可）。
Snapshot makeSnap({
  required String state,
  String? hostId = 'd-host',
  String? guestId = 'd-guest',
  Map<String, dynamic>? ready,
  Map<String, dynamic>? disconnected,
  String fen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
}) {
  return Snapshot(
    roomCode: 'ABCD',
    scriptHash: 'fake',
    scriptSrc: null,
    context: {
      'host_id': hostId,
      'guest_id': guestId,
      'players': <String, dynamic>{
        if (hostId != null) hostId: '房主',
        if (guestId != null) guestId: '访客',
      },
      if (ready != null) 'ready': ready,
      if (disconnected != null) 'disconnected': disconnected,
      'fen': fen,
      'moves': <dynamic>[],
      'status': 'playing',
    },
    state: state,
    version: 1,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    history: const [],
  );
}

/// 本地 = guest（黑方）。host = 'd-host'，guest = 'd-guest'。
FakeReadyHandle makeGuestHandle({Snapshot? initial}) {
  final transport = FakeTransport(deviceId: 'd-guest');
  return FakeReadyHandle(
    transport: transport,
    code: 'ABCD',
    initial: initial ??
        makeSnap(state: 'lobby', hostId: 'd-host', guestId: 'd-guest'),
  );
}

FakeReadyHandle makeHostHandle({Snapshot? initial}) {
  final transport = FakeTransport(deviceId: 'd-host');
  return FakeReadyHandle(
    transport: transport,
    code: 'ABCD',
    initial: initial ??
        makeSnap(state: 'lobby', hostId: 'd-host', guestId: 'd-guest'),
  );
}

Widget host(FakeReadyHandle handle) {
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

void main() {
  setUp(() => ChessSkinBundle.resetForTest());

  group('READY 门（lobby → ready → playing）', () {
    testWidgets('lobby 初始 → 渲染准备卡片（无开始游戏，有准备好了）', (tester) async {
      final handle = makeGuestHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      expect(find.text('等待对手'), findsOneWidget);
      expect(find.text('准备好了'), findsOneWidget, reason: 'lobby 双方未 ACK → 准备按钮');
      expect(find.text('开始游戏'), findsNothing);
    });

    testWidgets('双方 ACK 快照 → ready 卡片 + host 可见"开始游戏"', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      // 双方都已 ACK → 服务端 ready。
      handle.pushSnapshot(makeSnap(
        state: 'ready',
        ready: {'d-host': true, 'd-guest': true},
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('双方已就绪'), findsOneWidget);
      expect(find.textContaining('开始游戏'), findsOneWidget,
          reason: 'host 在 ready 后可见开始');
    });

    testWidgets('ready 卡片非 host（guest）→ 显示"等待房主开始…"', (tester) async {
      final handle = makeGuestHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      handle.pushSnapshot(makeSnap(
        state: 'ready',
        ready: {'d-host': true, 'd-guest': true},
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('双方已就绪'), findsOneWidget);
      expect(find.textContaining('等待房主开始'), findsOneWidget);
      expect(find.textContaining('开始游戏'), findsNothing);
    });

    testWidgets('点"准备好了" → 发 ACK action（乐观本地置位）', (tester) async {
      final handle = makeGuestHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      await tester.tap(find.text('准备好了'));
      await tester.pump();

      expect(handle.actionCalls, hasLength(1));
      expect(handle.actionCalls.first.$1, 'ACK');
      // 乐观本地置位：按钮变"已准备 ✓"
      expect(find.text('已准备 ✓'), findsOneWidget);
    });

    testWidgets('ready → host 点"开始游戏" → 发 DEAL', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      handle.pushSnapshot(makeSnap(
        state: 'ready',
        ready: {'d-host': true, 'd-guest': true},
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.textContaining('开始游戏'));
      await tester.pump();

      expect(handle.actionCalls, hasLength(1));
      expect(handle.actionCalls.first.$1, 'DEAL',
          reason: 'READY 门：host 显式 DEAL 开局');
    });
  });

  group('断连等重连（playing 内 disconnected 标记）', () {
    testWidgets('playing 快照 disconnected[我] → 显示"你已掉线"banner', (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();

      // 我方（guest）掉线 → 服务端 disconnected{guest}。
      handle.pushSnapshot(makeSnap(
        state: 'playing',
        disconnected: {'d-guest': true},
      ));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('你已掉线'), findsOneWidget);
    });

    testWidgets('掉线后同 device_id 重连（快照清 disconnected）→ banner 消失', (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();

      // 先掉线。
      handle.pushSnapshot(makeSnap(
        state: 'playing',
        disconnected: {'d-guest': true},
      ));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('你已掉线'), findsOneWidget);

      // 同 device_id 重连 → 服务端 on_join 清 disconnected。
      handle.pushSnapshot(makeSnap(state: 'playing'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('你已掉线'), findsNothing);
    });

    testWidgets('playing 快照 disconnected[对手] → 无"你已掉线"banner', (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();

      // 只有 host 掉线 → 我方（guest）不该显示"你已掉线"。
      handle.pushSnapshot(makeSnap(
        state: 'playing',
        disconnected: {'d-host': true},
      ));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('你已掉线'), findsNothing);
      // 棋盘仍渲染（房间 alive，等待 host 重连）。
      expect(find.byType(ChessBoard), findsOneWidget);
    });

    testWidgets('host 离开（playing → ended host_left）→ 终局卡片（"对局结束"）', (tester) async {
      // host 退出 = 房间销毁（Lua on_leave 的 host_left 分支）：guest 收到
      // ended 快照 + end_reason host_left → 渲染终局卡片。
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();

      handle.pushSnapshot(Snapshot(
        roomCode: 'ABCD',
        scriptHash: 'fake',
        scriptSrc: null,
        context: {
          'host_id': 'd-host',
          'guest_id': 'd-guest',
          'players': {'d-host': '房主', 'd-guest': '访客'},
          'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          'moves': <dynamic>[],
          'status': 'ended',
          'end_reason': 'host_left',
        },
        state: 'ended',
        version: 2,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        history: const [],
      ));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // guest 端看到终局卡片（无再来一局 —— RESET 仅 host，host 已离开）。
      expect(find.text('对局结束'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
    });
  });

  group('WS 瞬断 overlay（不退出页面）', () {
    testWidgets('closeEvents code=0 → overlay"连接断开，正在重连…"（不 pop）', (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();

      // 模拟 WS 断开（RoomHandle._onWSDone 发 close code 0）。
      handle.pushClose(code: 0);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('连接断开，正在重连'), findsOneWidget);
      // 页面未 pop（仍然渲染房间页内容）。
      expect(find.byType(ChessBoard), findsOneWidget);

      // 收到新快照 → overlay 消失。
      handle.pushSnapshot(makeSnap(state: 'playing'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('连接断开，正在重连'), findsNothing);
    });

    testWidgets('closeEvents code=4403（被踢）→ snackbar"已被踢出房间"（不 overlay）', (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();

      handle.pushClose(code: 4403, reason: 'kicked');
      await tester.pump();
      await tester.pump();

      // 终端关闭 → snackbar（不进 overlay）。
      expect(find.textContaining('已被踢出房间'), findsOneWidget);
      expect(find.textContaining('连接断开，正在重连'), findsNothing);
    });
  });

  group('ChessRoom 静态读取', () {
    test('readyMap / disconnectedPlayers / isHost / isGuest 解析正确', () {
      final snap = makeSnap(
        state: 'ready',
        ready: {'d-host': true, 'd-guest': false},
        disconnected: {'d-guest': true},
      );

      expect(ChessRoom.readyMap(snap), {'d-host': true, 'd-guest': false});
      expect(ChessRoom.disconnectedPlayers(snap), {'d-guest': true});
      expect(ChessRoom.isHost(snap, 'd-host'), isTrue);
      expect(ChessRoom.isHost(snap, 'd-guest'), isFalse);
      expect(ChessRoom.isGuest(snap, 'd-guest'), isTrue);
      expect(ChessRoom.isGuest(snap, 'd-host'), isFalse);

      // null 快照 → 空 map / false。
      expect(ChessRoom.readyMap(null), isEmpty);
      expect(ChessRoom.disconnectedPlayers(null), isEmpty);
      expect(ChessRoom.isHost(null, 'x'), isFalse);
    });
  });
}
