// test/lab/tetris_lua/tetris_playing_page_test.dart
//
// OnlineGamePage playing 阶段渲染回归测试 —— 真实 pump 对局页，
// 防止装饰清理/结构改动引入运行时布局异常（analyze 查不出来）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'package:xiaodouzi_fr/lab/demos/tetris_lua/constants.dart';
import 'package:xiaodouzi_fr/lab/demos/tetris_lua/widgets.dart';

Snapshot _playingSnapshot(String myId, String oppId) {
  List<List<int>> emptyBoard() => List.generate(
        kTetrisRows,
        (_) => List.filled(kTetrisCols, 0),
      );
  Map<String, dynamic> state(int score) => {
        'board': emptyBoard(),
        'score': score,
        'lines': 0,
        'pieceIndex': 3,
        'alive': true,
      };
  return Snapshot(
    roomCode: 'TEST01',
    scriptHash: 'abc',
    context: {
      'host_id': myId,
      'players': {myId: '我方', oppId: '对手'},
      'piece_sequence': List.generate(64, (i) => (i % 7) + 1),
      'states': {myId: state(120), oppId: state(80)},
    },
    state: 'playing',
    version: 2,
    createdAt: DateTime(2026, 9, 25),
    updatedAt: DateTime(2026, 9, 25),
    history: const [],
  );
}

void main() {
  testWidgets('playing 快照 → 对局页正常渲染（棋盘/侧栏/控制键）', (tester) async {
    const myId = 'did-1';
    const oppId = 'did-2';
    final transport = RelayV3Transport(
      relayUrl: 'http://127.0.0.1:1', // 不会真的联网；网络调用全部 catchError 吞掉
      alias: 'tester',
      deviceId: myId,
    );
    final handle = RoomHandle.testCreate(
      transport: transport,
      code: 'TEST01',
      wsUrl: 'ws://127.0.0.1:1/ws',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OnlineGamePage(
          handle: handle,
          onLeave: () async {},
        ),
      ),
    );
    await tester.pump();

    // 页面订阅完成后注入 playing 快照（真实时序：WS 推送晚于 initState）
    handle.debugEmitSnapshot(_playingSnapshot(myId, oppId));
    // 多 pump 几帧：snapshot 回调创建引擎 → 重排 → playing UI
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    // 对局页核心信息元素必须可见
    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('LINES'), findsOneWidget);
    expect(find.text('LEVEL'), findsOneWidget);
    expect(find.text('HOLD'), findsOneWidget);
    expect(find.text('NEXT'), findsOneWidget);
    expect(find.text('MOVE'), findsOneWidget);
    expect(find.text('ACTION'), findsOneWidget);
    // 控制键 6 个
    expect(find.text('左'), findsOneWidget);
    expect(find.text('软降'), findsOneWidget);
    expect(find.text('右'), findsOneWidget);
    expect(find.text('左旋'), findsOneWidget);
    expect(find.text('右旋'), findsOneWidget);
    expect(find.text('硬降'), findsOneWidget);
    // 对手栏
    expect(find.text('对手'), findsOneWidget);
    expect(find.text('80 · L0'), findsOneWidget);

    // 模拟按键操作不抛异常
    await tester.tap(find.text('左旋'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('硬降'));
    await tester.pump(const Duration(milliseconds: 50));

    await handle.dispose();
  });

  testWidgets('小屏（360×640）playing 渲染不抛布局异常', (tester) async {
    const myId = 'did-1';
    const oppId = 'did-2';
    final transport = RelayV3Transport(
      relayUrl: 'http://127.0.0.1:1',
      alias: 'tester',
      deviceId: myId,
    );
    final handle = RoomHandle.testCreate(
      transport: transport,
      code: 'TEST01',
      wsUrl: 'ws://127.0.0.1:1/ws',
    );
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: OnlineGamePage(handle: handle, onLeave: () async {}),
      ),
    );
    await tester.pump();
    handle.debugEmitSnapshot(_playingSnapshot(myId, oppId));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SCORE'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await handle.dispose();
  });
}
