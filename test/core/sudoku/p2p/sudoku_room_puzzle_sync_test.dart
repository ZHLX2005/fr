// test/core/sudoku/p2p/sudoku_room_puzzle_sync_test.dart
//
// 数独联机房间页题面一致性 —— 服务端允许在 lobby/ready 重复 SET_PUZZLE 覆盖
// ctx 题面（host 换难度 / 再次生成），客户端本地棋盘必须跟随重建。
// 回归背景：旧实现 `_board == null` 一次性构造守卫，重复生成后本地停留旧题面，
// SUBMIT 被服务端新 solution 静默拒绝（提交无任何反馈）。
//
// 测试模式与 chess_room_page_test 一致：FakeTransport（MockClient，不联网）
// + FakeRoomHandle.testCreate + 手动 pushSnapshot 模拟 WS 广播。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'package:xiaodouzi_fr/core/sudoku/p2p/sudoku_room_page.dart';
import 'package:xiaodouzi_fr/core/sudoku/widgets/sudoku_grid.dart';

class FakeTransport extends RelayV3Transport {
  FakeTransport({required super.deviceId})
      : super(
          relayUrl: 'http://fake',
          alias: 'me',
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        );
}

/// 覆写 snapshots 流（library-private，子类拿不到），支持手动 pushSnapshot
/// 模拟服务端 WS 广播；applyAction 记录调用并回显当前快照（PROGRESS 等）。
class FakeRoomHandle extends RoomHandle {
  final StreamController<Snapshot> _fakeSnapshots =
      StreamController<Snapshot>.broadcast();

  FakeRoomHandle({
    required FakeTransport transport,
    required super.code,
    super.initial,
  }) : super.testCreate(
          transport: transport,
          wsUrl: 'ws://fake/ws3/$code',
        );

  @override
  Stream<Snapshot> get snapshots => _fakeSnapshots.stream;

  void pushSnapshot(Snapshot snap) {
    latest = snap;
    if (!_fakeSnapshots.isClosed) _fakeSnapshots.add(snap);
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
}

/// 生成数独快照：state + 题面/答案 + 常规 context 字段。
Snapshot makeSnapshot({
  required String state,
  required List<int> puzzle,
  required List<int> solution,
  String difficulty = 'easy',
  int version = 1,
}) {
  return Snapshot(
    roomCode: 'ROOM1',
    scriptHash: 'fake',
    scriptSrc: null,
    context: {
      'host_id': 'device-host',
      'guest_id': 'device-guest',
      'puzzle': puzzle,
      'solution': solution,
      'seed': 42,
      'difficulty': difficulty,
      'progress': <String, dynamic>{},
      'finished_at_ms': <String, dynamic>{},
    },
    state: state,
    version: version,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    history: const [],
  );
}

/// 81 格题面：仅 [index] 格为 [v]（其余空格 0）——渲染上保证数字唯一可断言。
List<int> puzzleWith(int index, int v) => List<int>.filled(81, 0)..[index] = v;

/// 答案：81 格全 1（值域 1-9 即可，客户端不做答案校验）。
List<int> flatSolution() => List<int>.filled(81, 1);

Future<void> pumpRoom(WidgetTester tester, FakeRoomHandle handle) {
  return tester.pumpWidget(
    MaterialApp(home: SudokuRoomPage(handle: handle)),
  );
}

Finder gridText(String label) => find.descendant(
      of: find.byType(SudokuGrid),
      matching: find.text(label),
    );

void main() {
  testWidgets(
    'ready 态题面被覆盖：ready A → ready B → playing，本地棋盘跟随重建到 B',
    (tester) async {
      final handle = FakeRoomHandle(
        transport: FakeTransport(deviceId: 'device-host'),
        code: 'ROOM1',
        initial: makeSnapshot(
          state: 'ready',
          puzzle: puzzleWith(0, 5),
          solution: flatSolution(),
        ),
      );
      await pumpRoom(tester, handle);
      await tester.pump();

      // host 在 ready 态换难度 / 再点"生成题目" → 服务端覆盖题面为 B。
      handle.pushSnapshot(makeSnapshot(
        state: 'ready',
        puzzle: puzzleWith(0, 3),
        solution: flatSolution(),
        version: 2,
      ));
      await tester.pump();

      // START 开局 → playing 才渲染棋盘，此时必须是新题面 B。
      handle.pushSnapshot(makeSnapshot(
        state: 'playing',
        puzzle: puzzleWith(0, 3),
        solution: flatSolution(),
        version: 3,
      ));
      await tester.pump();

      expect(gridText('3'), findsOneWidget);
      expect(gridText('5'), findsNothing);
    },
  );

  testWidgets(
    'playing 态同题面快照不重建（保留玩家进度）；异题面快照以服务端为准重建',
    (tester) async {
      final handle = FakeRoomHandle(
        transport: FakeTransport(deviceId: 'device-host'),
        code: 'ROOM1',
        initial: makeSnapshot(
          state: 'playing',
          puzzle: puzzleWith(0, 5),
          solution: flatSolution(),
        ),
      );
      await pumpRoom(tester, handle);
      await tester.pump();

      // 选中空格 (0,1) 并填 7（题面 A 中该格为空 → 非题目初始格，可填）。
      final gridRect = tester.getRect(find.byType(SudokuGrid));
      final cell = gridRect.width / 9;
      await tester.tapAt(gridRect.topLeft + Offset(cell * 1.5, cell * 0.5));
      await tester.pump();
      await tester.tap(find.text('7')); // 键盘上唯一；棋盘 A 无 7
      await tester.pump();
      expect(gridText('7'), findsOneWidget);

      // 同题面快照（模拟 PROGRESS 回流等无关更新）→ 不重建，玩家进度保留。
      handle.pushSnapshot(makeSnapshot(
        state: 'playing',
        puzzle: puzzleWith(0, 5),
        solution: flatSolution(),
        version: 2,
      ));
      await tester.pump();
      expect(gridText('7'), findsOneWidget);

      // 异题面快照（防御路径，正常服务端不会在 playing 下覆盖）→ 重建，旧进度作废。
      handle.pushSnapshot(makeSnapshot(
        state: 'playing',
        puzzle: puzzleWith(0, 3),
        solution: flatSolution(),
        version: 3,
      ));
      await tester.pump();
      expect(gridText('3'), findsOneWidget);
      expect(gridText('7'), findsNothing);
      expect(gridText('5'), findsNothing);
    },
  );
}
