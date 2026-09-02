// test/core/chess/p2p/chess_lobby_page_test.dart
//
// ChessLobbyPage（社交房间号入口页）widget 测试：
//   · 表单校验：空昵称 / 短房间号 / 易混字符（0/O/1/I/L）
//   · 点击"进入对局" → tryJoinOrCreate(code=大写, script=kChessScript, maxPlayers=2)
//   · 成功 → 等待房 UI（房间号 chip + 等待朋友加入）
//   · 409 区分：code collision → 提示换号；join rejected → 提示满员
//   · 快照 state=playing → onStarted 触发一次
//   · host + guest 在场 → 房主可见"开始游戏" → START → playing 快照 → onStarted
//
// Fake：注入 transportBuilder（RecordingTransport 覆写 tryJoinOrCreate，
// 不联网）+ FakeLobbyHandle（RoomHandle.testCreate，不连 WS，手动推快照）。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xiaodouzi_fr/core/chess/endgame/chess_endgame.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_identity.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_lobby_page.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/script/chess_script.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_device_id.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 记录 tryJoinOrCreate 调用（code + script + maxPlayers + initialParams）。
///
/// v4 加 initialParams 字段用于 host_color picker 路径测试 ——
/// 老测试只用前 3 个字段，无破坏。
class _JoinCall {
  final String code;
  final String script;
  final int maxPlayers;
  final Map<String, dynamic> initialParams;
  _JoinCall(this.code, this.script, this.maxPlayers, this.initialParams);
}

/// 真实 RelayV3Transport + MockClient（不联网）；覆写 tryJoinOrCreate。
class RecordingTransport extends RelayV3Transport {
  RecordingTransport({required String deviceId})
    : super(
        relayUrl: 'http://fake',
        alias: 'me',
        deviceId: deviceId,
        httpClient: MockClient((req) async => http.Response('{}', 200)),
      );

  final List<_JoinCall> joinCalls = [];
  RoomHandle? handleToReturn;
  RelayV3Exception? failWith;

  @override
  Future<RoomHandle> tryJoinOrCreate({
    required String code,
    required String script,
    required Map<String, dynamic> initialParams,
    int maxPlayers = 8,
  }) async {
    joinCalls.add(_JoinCall(code, script, maxPlayers, initialParams));
    final e = failWith;
    if (e != null) throw e;
    return handleToReturn!;
  }
}

/// Fake RoomHandle —— RoomHandle.testCreate（不连 WS），手动推快照模拟广播。
class FakeLobbyHandle extends RoomHandle {
  final StreamController<Snapshot> _ctrl = StreamController<Snapshot>.broadcast();

  FakeLobbyHandle({
    required RecordingTransport transport,
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

  void pushSnapshot(Snapshot snap) {
    latest = snap;
    if (!_ctrl.isClosed) _ctrl.add(snap);
  }

  @override
  Future<Snapshot> applyAction({
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    String? sourceDeviceId,
  }) async {
    return latest!;
  }

  @override
  Future<void> dispose() async {
    await _ctrl.close();
  }
}

/// 安装假 async SharedPreferences 存储并返回它（每次新建 = 模拟重启/新会话）。
InMemorySharedPreferencesAsync installInMemoryPrefs({
  Map<String, Object> seed = const {},
}) {
  final store = InMemorySharedPreferencesAsync.withData(seed);
  SharedPreferencesAsyncPlatform.instance = store;
  return store;
}

/// 生成一份快照（lobby / playing 均可）。
Snapshot makeSnap({
  required String state,
  String? hostId = 'd-me',
  String? guestId,
  String? forDevice,
}) {
  return Snapshot(
    roomCode: 'ABCD',
    scriptHash: 'fake',
    scriptSrc: null,
    context: {
      'host_id': hostId,
      'guest_id': guestId,
      'players': <String, dynamic>{
        if (hostId != null) hostId: '我',
        if (guestId != null) guestId: '对手',
      },
      'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
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


// Finder helper：匹配包含子串的 Text 或 RichText。config 页 chip 用
// RichText 渲染（label + sublabel），find.textContaining 找不到子 span，
// 所以用 byWidgetPredicate 遍历 widget tree 自己匹配。
Finder _chipContaining(String s) => find.byWidgetPredicate((w) {
  if (w is Text) return w.data?.contains(s) ?? false;
  if (w is RichText) {
    final span = w.text;
    if (span is TextSpan) return span.toPlainText().contains(s);
  }
  return false;
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({}); // legacy（RelayDeviceId）
    RelayDeviceId.debugReset();
    installInMemoryPrefs(); // async（ChessIdentity）
    ChessIdentity.debugReset();
  });

  tearDown(() {
    ChessIdentity.debugReset();
    RelayDeviceId.debugReset();
  });

  Widget host({required RecordingTransport transport, required List<RoomHandle> joined}) {
    return MaterialApp(
      home: ChessLobbyPage(
        relayUrl: 'http://fake',
        onStarted: joined.add,
        transportBuilder: (alias, deviceId) => transport,
      ),
    );
  }

  Future<void> fillAndGo(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'abcd');
    await tester.tap(find.text("加入房间").last);
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('表单校验：空昵称 → 提示输入昵称（不发请求）', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));

    await tester.enterText(find.byType(TextField).at(0), ' ');
    await tester.enterText(find.byType(TextField).at(1), 'ABCD');
    await tester.tap(find.text("加入房间").last);
    await tester.pump();

    expect(find.text('请输入昵称'), findsOneWidget);
    expect(transport.joinCalls, isEmpty);
  });

  testWidgets('表单校验：房间号过短 → 提示 4–6 位（不发请求）', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));

    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'AB');
    await tester.tap(find.text("加入房间").last);
    await tester.pump();

    expect(find.text('房间号为 4–6 位大写字母数字'), findsOneWidget);
    expect(transport.joinCalls, isEmpty);
  });

  testWidgets('表单校验：易混字符（0/O/1/I/L）→ 提示不可用（服务端 400 防线）', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));

    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'AB0D');
    await tester.tap(find.text("加入房间").last);
    await tester.pump();

    expect(find.textContaining('易混淆'), findsOneWidget);
    expect(transport.joinCalls, isEmpty);
  });

  testWidgets('进入对局 → tryJoinOrCreate(code 大写, kChessScript, maxPlayers=2) + 等待房 UI',
      (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: null),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));

    await fillAndGo(tester);

    expect(transport.joinCalls, hasLength(1));
    expect(transport.joinCalls.first.code, 'ABCD', reason: '小写输入应转大写');
    expect(transport.joinCalls.first.script, kChessScript);
    expect(transport.joinCalls.first.maxPlayers, 2);
    // 等待房：房间号 chip + 等待朋友加入
    expect(find.text('ABCD'), findsOneWidget);
    expect(find.textContaining('等待朋友加入'), findsOneWidget);
    expect(joined, isEmpty, reason: 'playing 前不触发 onStarted');
  });

  testWidgets('409 code collision → 提示换号；409 join rejected → 提示满员', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    transport.failWith = RelayV3Exception(409, 'code collision after retries');
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));
    await fillAndGo(tester);
    expect(find.text('房间号 ABCD 已被占用，请换一个'), findsOneWidget);

    // 换成满员错误重试
    transport.failWith = RelayV3Exception(409, 'join rejected by script');
    await tester.tap(find.text("加入房间").last);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('房间 ABCD 已满员，无法加入'), findsOneWidget);
    expect(joined, isEmpty);
  });

  testWidgets('快照 state=playing → onStarted 触发一次（推流风暴不重复）', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: 'd-guest'),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));
    await fillAndGo(tester);

    handle.pushSnapshot(makeSnap(state: 'playing', guestId: 'd-guest'));
    await tester.pump();
    await tester.pump();
    expect(joined, hasLength(1));

    // 同一房间的后续 playing 快照（走子）不得再次触发
    handle.pushSnapshot(makeSnap(state: 'playing', guestId: 'd-guest'));
    await tester.pump();
    await tester.pump();
    expect(joined, hasLength(1));
  });

  testWidgets('host + guest 在场 → 显示"双方已就绪，进入准备…"（等待房瞬态）', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: 'd-guest'),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));
    await fillAndGo(tester);

    // v2 READY 门：双人到齐后停在 lobby 准备阶段 —— 等待房提示"进入准备…"，
    // 不自动开局（"开始游戏"在房间页由 host 显式点 DEAL）。
    expect(find.textContaining('进入准备'), findsOneWidget);
    expect(find.text('开始游戏'), findsNothing);
    expect(find.textContaining('执白'), findsWidgets, reason: 'host = 白方先手标注');
    expect(find.textContaining('执黑'), findsOneWidget);
  });

  testWidgets('lobby 快照 → onStarted 触发（READY 门：不等 playing 即 push 房间页）', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: 'd-guest'),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));
    await fillAndGo(tester);

    // 玩家（guest 加入）广播 lobby 快照 → v2 立即 push 房间页（不等 playing）。
    handle.pushSnapshot(makeSnap(state: 'lobby', guestId: 'd-guest'));
    await tester.pump();
    await tester.pump();
    expect(joined, hasLength(1), reason: 'lobby（准备阶段）即应 push 房间页');
  });

  testWidgets('guest 加入（ready 快照）→ onStarted 触发（READY 门）', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: null),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));
    await fillAndGo(tester);
    expect(find.textContaining('等待朋友加入'), findsOneWidget);
    expect(joined, isEmpty);

    // 服务端 on_join 后停在 lobby；双方 ACK 后进 ready —— 两种都触发 onStarted。
    handle.pushSnapshot(makeSnap(state: 'ready', guestId: 'd-guest'));
    await tester.pump();
    await tester.pump();
    expect(joined, hasLength(1), reason: 'ready（双方已 ACK）也应 push 房间页');
  });

  testWidgets('guest 加入（playing 快照）→ 开局 onStarted 触发', (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: null),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];
    await tester.pumpWidget(host(transport: transport, joined: joined));
    await fillAndGo(tester);
    expect(find.textContaining('等待朋友加入'), findsOneWidget);
    expect(joined, isEmpty);

    // 服务端 on_join 双人到齐后停在 lobby；host 点"开始游戏"（DEAL）→ playing。
    handle.pushSnapshot(makeSnap(state: 'playing', guestId: 'd-guest'));
    await tester.pump();
    await tester.pump();
    expect(joined, hasLength(1));
  });

  // ─────────────── 稳定身份（Bug 1/2 根因）：真实登录 userId 流入 transport ───────────────

  testWidgets('已登录 → transport 收到 uid-<userId>（真实登录 uid 优先）', (tester) async {
    installInMemoryPrefs(seed: {ChessIdentity.userIdKey: '42'});
    String? capturedDeviceId;
    final transport = RecordingTransport(deviceId: 'uid-42');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: null),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ChessLobbyPage(
          relayUrl: 'http://fake',
          onStarted: joined.add,
          transportBuilder: (alias, deviceId) {
            capturedDeviceId = deviceId;
            return transport;
          },
        ),
      ),
    );
    await fillAndGo(tester);

    expect(capturedDeviceId, 'uid-42',
        reason: '已登录 → 真实登录 userId 作为玩家身份（非 token/非会话 deviceId）');
    expect(transport.joinCalls, hasLength(1));
  });

  testWidgets('未登录 → transport 收到设备级 UUID（回退，不以空身份进房）', (tester) async {
    // 无 userId → 回退设备级 UUID（稳定）。
    String? capturedDeviceId;
    final transport = RecordingTransport(deviceId: 'whatever');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: null),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ChessLobbyPage(
          relayUrl: 'http://fake',
          onStarted: joined.add,
          transportBuilder: (alias, deviceId) {
            capturedDeviceId = deviceId;
            return transport;
          },
        ),
      ),
    );
    await fillAndGo(tester);

    expect(capturedDeviceId, isNotNull);
    expect(capturedDeviceId, isNotEmpty);
    expect(capturedDeviceId, startsWith('dev-'),
        reason: '未登录回退设备级 UUID（稳定）');
  });

  testWidgets('同一稳定身份二次进房：tryJoinOrCreate 正常走（不因新 session 误判新玩家）', (
    tester,
  ) async {
    installInMemoryPrefs(seed: {ChessIdentity.userIdKey: '42'});
    final transport = RecordingTransport(deviceId: 'uid-42');
    final handle = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby', guestId: null, hostId: 'uid-42'),
    );
    transport.handleToReturn = handle;
    final joined = <RoomHandle>[];

    // 第一次进房（模拟 host 建房）。
    await tester.pumpWidget(host(transport: transport, joined: joined));
    await fillAndGo(tester);
    expect(transport.joinCalls, hasLength(1));
    expect(find.text('ABCD'), findsOneWidget);

    // 同 session 内重置回入口（模拟断线重连 / 退房重进）→ 再次 join。
    await tester.tap(find.byTooltip('断开'));
    await tester.pump();
    await tester.pump();
    await fillAndGo(tester);
    expect(transport.joinCalls, hasLength(2), reason: '同一稳定身份重进走 join');
  });


  // ══════════════════════════════════════════════════════════════
  // v6: 双入口（创建房间 / 加入房间）+ ChessRoomConfigPage 配置
  // ══════════════════════════════════════════════════════════════

  Widget hostWithEndgame({
    required RecordingTransport transport,
    required List<RoomHandle> joined,
    ChessEndgameSnapshot? endgame,
  }) {
    return MaterialApp(
      home: ChessLobbyPage(
        relayUrl: 'http://fake',
        onStarted: joined.add,
        transportBuilder: (alias, deviceId) => transport,
        initialEndgame: endgame,
      ),
    );
  }

  testWidgets('v6 host 默认（无 endgame）→ initialParams.host_color=w + first_mover=w', (
    tester,
  ) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    transport.handleToReturn = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby'),
    );
    await tester.pumpWidget(host(transport: transport, joined: joined));

    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'ABCD');
    await tester.ensureVisible(find.text("创建房间").last);
    await tester.tap(find.text("创建房间").last);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text("创建房间").last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(transport.joinCalls, hasLength(1));
    final p = transport.joinCalls.first.initialParams;
    expect(p['host_color'], 'w');
    expect(p['guest_color'], 'b');
    expect(p['first_mover'], 'w');
  });

  testWidgets("v6 host 切到我执黑他执白 → host=b, guest=w", (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    transport.handleToReturn = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby'),
    );
    await tester.pumpWidget(host(transport: transport, joined: joined));

    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'ABCD');
    await tester.ensureVisible(find.text("创建房间").last);
    await tester.tap(find.text("创建房间").last);
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(_chipContaining("我执黑，他执白"));
    await tester.tap(_chipContaining("我执黑，他执白"));
    await tester.pump();
    await tester.tap(find.text("创建房间").last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(transport.joinCalls, hasLength(1));
    final p = transport.joinCalls.first.initialParams;
    expect(p['host_color'], 'b');
    expect(p['guest_color'], 'w');
    expect(p['first_mover'], 'w');
  });

  testWidgets("v6 host 切到随机掷筛 → host=random, guest=null", (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    transport.handleToReturn = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby'),
    );
    await tester.pumpWidget(host(transport: transport, joined: joined));

    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'ABCD');
    await tester.ensureVisible(find.text("创建房间").last);
    await tester.tap(find.text("创建房间").last);
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(_chipContaining("随机掷筛"));
    await tester.tap(_chipContaining("随机掷筛"));
    await tester.pump();
    await tester.tap(find.text("创建房间").last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(transport.joinCalls, hasLength(1));
    final p = transport.joinCalls.first.initialParams;
    expect(p['host_color'], 'random');
    expect(p.containsKey('guest_color'), isFalse,
        reason: 'random 时不带 guest_color（服务端掷筛决定）');
  });

  testWidgets(
      'v6 endgame host 路径：默认 host=白/first_mover=黑 → host=w, first_mover=b', (
    tester,
  ) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    transport.handleToReturn = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby'),
    );
    final endgame = ChessEndgameSnapshot(
      label: '黑先残局',
      fen: '1r1bk2r/5ppp/3p3n/p1p1p3/4P1PP/2BP2P1/PP2B3/2KR2NR b k - 3 21',
    );
    await tester.pumpWidget(hostWithEndgame(
      transport: transport,
      joined: joined,
      endgame: endgame,
    ));

    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'ABCD');
    await tester.ensureVisible(find.text("创建房间").last);
    await tester.tap(find.text("创建房间").last);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text("创建房间").last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(transport.joinCalls, hasLength(1));
    final p = transport.joinCalls.first.initialParams;
    expect(p['initial_fen'], endgame.fen);
    expect(p['host_color'], 'w');
    expect(p['first_mover'], 'b');
  });

  testWidgets('v6 endgame host 切到 host=黑 + first_mover=黑 → host=b, first_mover=b',
      (tester) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    transport.handleToReturn = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby'),
    );
    final endgame = ChessEndgameSnapshot(
      label: '黑先残局',
      fen: '1r1bk2r/5ppp/3p3n/p1p1p3/4P1PP/2BP2P1/PP2B3/2KR2NR b k - 3 21',
    );
    await tester.pumpWidget(hostWithEndgame(
      transport: transport,
      joined: joined,
      endgame: endgame,
    ));

    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'ABCD');
    await tester.ensureVisible(find.text("创建房间").last);
    await tester.tap(find.text("创建房间").last);
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(_chipContaining("我执黑，他执白"));
    await tester.tap(_chipContaining("我执黑，他执白"));
    await tester.pump();
    await tester.tap(find.text("创建房间").last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(transport.joinCalls, hasLength(1));
    final p = transport.joinCalls.first.initialParams;
    expect(p['host_color'], 'b');
    expect(p['guest_color'], 'w');
    expect(p['first_mover'], 'b');
  });

  testWidgets('v6 加入房间路径：直接 tryJoinOrCreate，initialParams 最小', (
    tester,
  ) async {
    final transport = RecordingTransport(deviceId: 'd-me');
    final joined = <RoomHandle>[];
    transport.handleToReturn = FakeLobbyHandle(
      transport: transport,
      code: 'ABCD',
      initial: makeSnap(state: 'lobby'),
    );
    final endgame = ChessEndgameSnapshot(
      label: '黑先残局',
      fen: '1r1bk2r/5ppp/3p3n/p1p1p3/4P1PP/2BP2P1/PP2B3/2KR2NR b k - 3 21',
    );
    await tester.pumpWidget(hostWithEndgame(
      transport: transport,
      joined: joined,
      endgame: endgame,
    ));

    await tester.enterText(find.byType(TextField).at(0), '小白');
    await tester.enterText(find.byType(TextField).at(1), 'ABCD');
    await tester.ensureVisible(find.text('加入房间'));
    await tester.tap(find.text('加入房间'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(transport.joinCalls, hasLength(1));
    final p = transport.joinCalls.first.initialParams;
    expect(p['device_id'], isNotNull);
    expect(p['alias'], '小白');
    expect(p.containsKey('initial_fen'), isFalse, reason: 'guest 路径忽略残局');
    expect(p.containsKey('host_color'), isFalse);
    expect(p.containsKey('first_mover'), isFalse);
  });
}
