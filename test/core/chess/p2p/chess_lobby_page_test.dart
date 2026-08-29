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
import 'package:xiaodouzi_fr/core/chess/p2p/chess_lobby_page.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_script.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

/// 记录 tryJoinOrCreate 调用（code + script + maxPlayers）。
class _JoinCall {
  final String code;
  final String script;
  final int maxPlayers;
  _JoinCall(this.code, this.script, this.maxPlayers);
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
    joinCalls.add(_JoinCall(code, script, maxPlayers));
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
    await tester.tap(find.text('进入对局'));
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
    await tester.tap(find.text('进入对局'));
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
    await tester.tap(find.text('进入对局'));
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
    await tester.tap(find.text('进入对局'));
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
    await tester.tap(find.text('进入对局'));
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

  testWidgets('host + guest 在场 → 显示"双方已就绪，自动开局"（无开始按钮）', (tester) async {
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

    // 无准备按钮：双人到齐只提示自动开局（不出现"开始游戏"按钮）。
    expect(find.textContaining('自动开局'), findsOneWidget);
    expect(find.text('开始游戏'), findsNothing);
    expect(find.textContaining('执白'), findsWidgets, reason: 'host = 白方先手标注');
    expect(find.textContaining('执黑'), findsOneWidget);
  });

  testWidgets('guest 加入（playing 快照）→ 自动开局 onStarted 触发', (tester) async {
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

    // 服务端 on_join 在双人到齐时自动置 playing → 无需点"开始游戏"即触发 onStarted。
    handle.pushSnapshot(makeSnap(state: 'playing', guestId: 'd-guest'));
    await tester.pump();
    await tester.pump();
    expect(joined, hasLength(1));
  });
}
