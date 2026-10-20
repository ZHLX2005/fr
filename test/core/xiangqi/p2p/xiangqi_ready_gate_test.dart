// test/core/xiangqi/p2p/xiangqi_ready_gate_test.dart
//
// XiangqiRoomPage READY 门 + 断连重连 专项测试（对齐 chess_ready_gate_test.dart
// / draughts 同款房间页专项测试）。
//
// 场景覆盖：
//   · lobby → 双方 ACK → ready → host DEAL → playing（READY 门全流程）
//   · ready 卡片：host 可见「开始游戏」，guest 只看到「等待房主开始…」
//   · 点「准备好了」→ 发 ACK action（乐观本地置位）
//   · playing → 快照 disconnected[myId] → 「你已掉线」banner + 棋盘冻结
//   · playing → WS close code 0（瞬断）→ 「连接断开，正在重连…」overlay
//   · 权限表驱动：guest 拿不到 DEAL 权限 → 不出现「开始游戏」按钮
//
// Fake 复用真实 RoomHandle + 真实 RelayV3Transport（MockClient 不联网）+
// RoomHandle.testCreate 注入初始快照 —— 手动 pushSnapshot 模拟 WS 广播。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'package:xiaodouzi_fr/core/xiangqi/constants/xiangqi_constants.dart';
import 'package:xiaodouzi_fr/core/xiangqi/p2p/xiangqi_room_page.dart';

/// 真实 RelayV3Transport + MockClient（不联网）。
class FakeTransport extends RelayV3Transport {
  FakeTransport({required super.deviceId})
      : super(
          relayUrl: 'http://fake',
          alias: 'me',
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
    required super.code,
    super.initial,
  }) : super.testCreate(
          transport: transport,
          wsUrl: 'ws://fake/ws3/$code',
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
    if (!_closeCtrl.isClosed) {
      _closeCtrl.add(WSCloseEvent(code: code, reason: reason));
    }
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
///
/// `permissions` 缺省时带**与服务端 Lua on_init 同表**的 action 权限表
/// （真实服务端一直下发；缺了会让 canPerform 兜底放行）。
Snapshot makeSnap({
  required String state,
  String? hostId = 'd-host',
  String? guestId = 'd-guest',
  Map<String, dynamic>? ready,
  Map<String, dynamic>? disconnected,
  String fen = kXiangqiStartingFen,
  bool withPermissions = true,
}) {
  return Snapshot(
    roomCode: 'ABCD',
    scriptHash: 'fake',
    scriptSrc: null,
    context: {
      'host_id': hostId,
      'guest_id': guestId,
      'players': <String, dynamic>{
        ?hostId: '房主',
        ?guestId: '访客',
      },
      if (ready != null) 'ready': ready,
      if (disconnected != null) 'disconnected': disconnected,
      'fen': fen,
      'moves': <dynamic>[],
      'status': 'playing',
      'host_color': 'r',
      'initial_side': 'r',
      if (withPermissions)
        'action_permissions': <String, String>{
          'ACK': 'any',
          'DEAL': 'host',
          'SET_RULES': 'host',
          'MOVE': 'current_player',
          'RESIGN': 'any',
          'DRAW_OFFER': 'any',
          'DRAW_ACCEPT': 'any',
          'DRAW_DECLINE': 'any',
          'UNDO_OFFER': 'any',
          'UNDO_ACCEPT': 'any',
          'UNDO_DECLINE': 'any',
          'CLAIM_END': 'non_current_player',
          'RESET': 'host',
        },
    },
    state: state,
    version: 1,
    createdAt: DateTime.now().toUtc(),
    updatedAt: DateTime.now().toUtc(),
    history: const [],
  );
}

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
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 600,
          height: 700,
          child: XiangqiRoomPage(
            handle: handle,
            onLeave: () async {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('READY 门（lobby → ready → playing）', () {
    testWidgets('lobby 初始 → 渲染准备卡片（无开始游戏，有准备好了）',
        (tester) async {
      final handle = makeGuestHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      expect(find.text('等待对手'), findsOneWidget);
      expect(find.text('准备好了'), findsOneWidget);
      expect(find.textContaining('开始游戏'), findsNothing);
    });

    testWidgets('双方 ACK 快照 → ready 卡片 + host 可见「开始游戏」',
        (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      handle.pushSnapshot(makeSnap(
        state: 'ready',
        ready: {'d-host': true, 'd-guest': true},
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('双方已就绪'), findsOneWidget);
      expect(find.textContaining('开始游戏'), findsOneWidget);
    });

    testWidgets('ready 卡片非 host（guest）→ 显示「等待房主开始…」',
        (tester) async {
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

    testWidgets('点「准备好了」→ 发 ACK action（乐观本地置位）', (tester) async {
      final handle = makeGuestHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      await tester.tap(find.text('准备好了'));
      await tester.pump();

      expect(handle.actionCalls, hasLength(1));
      expect(handle.actionCalls.first.$1, 'ACK');
      // 乐观本地置位：按钮变「已准备 ✓」
      expect(find.text('已准备 ✓'), findsOneWidget);
    });

    testWidgets('ready → host 点「开始游戏」→ 发 DEAL', (tester) async {
      final handle = makeHostHandle();
      await tester.pumpWidget(host(handle));
      await tester.pump();

      handle.pushSnapshot(makeSnap(
        state: 'ready',
        ready: {'d-host': true, 'd-guest': true},
      ));
      await tester.pump();
      await tester.pump();

      // 准备卡含规则面板后更高 → 滚动到可见再点。
      final dealBtn = find.textContaining('开始游戏');
      await tester.ensureVisible(dealBtn);
      await tester.pump();
      await tester.tap(dealBtn);
      await tester.pump();

      expect(handle.actionCalls.any((c) => c.$1 == 'DEAL'), isTrue);
    });

    testWidgets('playing → 渲染棋盘 + 操作条（认输/悔棋/求和三按钮）',
        (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();
      await tester.pump();

      expect(find.text('认输'), findsOneWidget);
      expect(find.text('悔棋'), findsOneWidget);
      expect(find.text('求和'), findsOneWidget);
    });
  });

  group('断线 / 重连', () {
    testWidgets('快照 disconnected 含自己 → 显示「你已掉线」banner',
        (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();
      await tester.pump();

      handle.pushSnapshot(makeSnap(
        state: 'playing',
        disconnected: {'d-guest': true},
      ));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('你已掉线'), findsOneWidget);
    });

    testWidgets('WS 瞬断（code 0）→ 显示「连接断开，正在重连…」overlay',
        (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();
      await tester.pump();

      handle.pushClose(code: 0);
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('连接断开'), findsOneWidget);
    });

    testWidgets('掉线后新快照清 disconnected → banner 消失', (tester) async {
      final handle = makeGuestHandle(
        initial: makeSnap(state: 'playing'),
      );
      await tester.pumpWidget(host(handle));
      await tester.pump();
      await tester.pump();

      handle.pushSnapshot(makeSnap(
        state: 'playing',
        disconnected: {'d-guest': true},
      ));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('你已掉线'), findsOneWidget);

      handle.pushSnapshot(makeSnap(state: 'playing'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('你已掉线'), findsNothing);
    });
  });
}
