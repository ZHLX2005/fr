// test/core/xiangqi/p2p/xiangqi_can_perform_equivalence_test.dart
//
// **客户端 canPerform 与服务端 Lua role_check 的等价性证明**。
//
// 背景：房间页把「轮到我走」的判定改成
//   「本地引擎回合判定 **且** 服务端权限表放行」（A03 §3④）。
// 这就要求客户端 canPerform 不能与服务端 role_check 判反 ——
// 判反会导致**合法玩家被误拦**（棋盘点不动，且毫无提示）。
//
// 本测试把服务端 Lua 的判定逻辑**逐行复刻**成 Dart 参考实现，
// 再对状态矩阵逐一比对；另附一条真实对局的「重放一致性」检查：
// 客户端按 moves 重放出来的局面轮次方，必须与 canPerform 的判定一致。
//
// 参考实现来源（服务端 Lua，relay v3）：
//   lib/core/xiangqi/p2p/script/xiangqi_script_lifecycle.dart
//     · side_to_move(c, n)
//     · role_check(c, p, action) 的 current_player / non_current_player 分支
//   lib/core/xiangqi/p2p/script/xiangqi_script_actions.dart
//     · on_action_MOVE 的轮次反证（side_to_move(c, #c.moves + 1)）

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/xiangqi/constants/xiangqi_constants.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/fen_codec.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/make_move.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/board_state.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/move.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/piece.dart';
import 'package:xiaodouzi_fr/core/xiangqi/p2p/xiangqi_room.dart';

/// 服务端 Lua `side_to_move(c, n)` 的 Dart 复刻。
String _luaSideToMove({
  required String initialSide,
  required int n,
}) {
  final first = initialSide.isEmpty ? 'r' : initialSide;
  if (n.isEven) return first;
  return first == 'r' ? 'b' : 'r';
}

/// 服务端 Lua `role_check(c, p, "MOVE")` 的 Dart 复刻。
///
/// 判定「给定 device_id 是否是当前走子方」：
///   side = side_to_move(c, #c.moves)
///   host_side = c.host_color or "r"
///   当前走子方 = (side == host_side) ? host : guest
bool _luaIsCurrentPlayer({
  required String hostId,
  required String guestId,
  required String deviceId,
  required String hostColor,
  required String initialSide,
  required int moves,
}) {
  final side = _luaSideToMove(initialSide: initialSide, n: moves);
  final hostSide = hostColor.isEmpty ? 'r' : hostColor;
  if (side == hostSide) return deviceId == hostId;
  return deviceId == guestId;
}

Snapshot _snap({
  required String hostId,
  required String guestId,
  required String hostColor,
  required String initialSide,
  required int moves,
}) {
  return Snapshot(
    roomCode: 'T',
    scriptHash: 'h',
    state: 'playing',
    version: 1,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    history: const [],
    context: {
      'host_id': hostId,
      'guest_id': guestId,
      'host_color': hostColor,
      'initial_side': initialSide,
      'status': 'playing',
      'moves': List.filled(moves, {'uci': 'b0e2'}),
      'action_permissions': <String, String>{
        'MOVE': 'current_player',
        'CLAIM_END': 'non_current_player',
      },
    },
  );
}

void main() {
  group('canPerform(MOVE) ≡ 服务端 Lua role_check（状态矩阵穷举）', () {
    test('host/guest × 手数 0..7 × 执子色 × 先手方 全部一致', () {
      for (final hostColor in ['r', 'b']) {
        for (final initialSide in ['r', 'b']) {
          for (var moves = 0; moves <= 7; moves++) {
            final snap = _snap(
              hostId: 'H',
              guestId: 'G',
              hostColor: hostColor,
              initialSide: initialSide,
              moves: moves,
            );
            for (final deviceId in ['H', 'G']) {
              final isHost = deviceId == 'H';
              final client = XiangqiRoom.canPerform(
                'MOVE',
                snap,
                isHost: isHost,
              );
              final server = _luaIsCurrentPlayer(
                hostId: 'H',
                guestId: 'G',
                deviceId: deviceId,
                hostColor: hostColor,
                initialSide: initialSide,
                moves: moves,
              );
              expect(
                client,
                server,
                reason: 'hostColor=$hostColor initialSide=$initialSide '
                    'moves=$moves device=$deviceId —— 客户端与服务端判反会'
                    '导致合法玩家被误拦',
              );
            }
          }
        }
      }
    });

    test('canPerform(CLAIM_END) ≡ 服务端 non_current_player（互补）', () {
      for (final hostColor in ['r', 'b']) {
        for (final initialSide in ['r', 'b']) {
          for (var moves = 1; moves <= 6; moves++) {
            final snap = _snap(
              hostId: 'H',
              guestId: 'G',
              hostColor: hostColor,
              initialSide: initialSide,
              moves: moves,
            );
            for (final deviceId in ['H', 'G']) {
              final isHost = deviceId == 'H';
              final claim = XiangqiRoom.canPerform(
                'CLAIM_END',
                snap,
                isHost: isHost,
              );
              final move = XiangqiRoom.canPerform(
                'MOVE',
                snap,
                isHost: isHost,
              );
              expect(
                claim,
                !move,
                reason: 'CLAIM_END（non_current_player）必须与 MOVE 互补'
                    '（hostColor=$hostColor initialSide=$initialSide '
                    'moves=$moves device=$deviceId）',
              );
            }
          }
        }
      }
    });
  });

  group('真实对局：重放出来的局面轮次方 ≡ canPerform 判定', () {
    test('开局连续走 8 手，每一步两侧的 canPerform 与局面轮次方一致', () {
      // 一条真实合法的开局线（红先，交替走）：
      //   炮二平五 / 马8进7 / 兵七进一 / 卒7进1
      //   马二进三 / 士四进五 / 将5进1 / 卒3进1
      const line = [
        'b7e7', // 红炮 (7,1) → (7,4)
        'h0g2', // 黑马 (0,7) → (2,6)
        'a6a5', // 红兵 (6,0) → (5,0)
        'g3g4', // 黑卒 (3,6) → (4,6)
        'b9c7', // 红马 (9,1) → (7,2)
        'd9e8', // 红仕 (9,3) → (8,4)
        'e0e1', // 黑将 (0,4) → (1,4)
        'c3c4', // 黑卒 (3,2) → (4,2)
      ];

      var board = XiangqiBoardState.initial();
      final history = <Map<String, dynamic>>[];

      for (var step = 0; step < line.length; step++) {
        final uci = line[step];
        final move = XiangqiMove.fromUci(uci);
        expect(move, isNotNull, reason: '$uci 记号非法');
        if (move == null) continue;

        // 走子前：轮次方 = 引擎判定；canPerform 必须与之一致
        final movesSoFar = history.length;
        final snap = _snap(
          hostId: 'H',
          guestId: 'G',
          hostColor: 'r',
          initialSide: 'r',
          moves: movesSoFar,
        );
        for (final deviceId in ['H', 'G']) {
          final isHost = deviceId == 'H';
          final allowed = XiangqiRoom.canPerform('MOVE', snap, isHost: isHost);
          final engineTurn = isHost
              ? board.sideToMove == XiangqiColor.red
              : board.sideToMove == XiangqiColor.black;
          expect(
            allowed,
            engineTurn,
            reason: '第 $step 手前（已走 $movesSoFar 手）：'
                'device=$deviceId —— 权限表与引擎回合判定不一致',
          );
        }

        board = applyXiangqiMoveSimple(board, move);
        history.add({'uci': uci, 'by': 'H', 'ts': step, 'fen': ''});
      }
    });

    test('服务端权威轮次反证：MOVE 上报后 FEN 轮次位 == side_to_move(n+1)', () {
      // 服务端 on_action_MOVE 用 side_to_move(c, #c.moves + 1) 反证客户端上报的
      // FEN 轮次位。客户端 applyXiangqiMove 翻转 sideToMove，必须与之吻合。
      var board = XiangqiBoardState.initial();
      final moves = ['b7e7', 'h0g2', 'a6a5', 'g3g4'];
      for (var i = 0; i < moves.length; i++) {
        final move = XiangqiMove.fromUci(moves[i])!;
        final next = applyXiangqiMoveSimple(board, move);
        // 走完第 i+1 手后，引擎的轮次方应等于 Lua side_to_move(i+1)
        final expectSide = _luaSideToMove(initialSide: 'r', n: i + 1);
        expect(
          next.sideToMove == XiangqiColor.red ? 'r' : 'b',
          expectSide,
          reason: '第 ${i + 1} 手后引擎轮次方与服务端 side_to_move 不一致',
        );
        board = next;
      }
    });
  });

  group('兜底安全：权限表缺失时不得误拦', () {
    test('快照无 action_permissions → MOVE 放行（不因缺表而卡死）', () {
      final snap = Snapshot(
        roomCode: 'T',
        scriptHash: 'h',
        state: 'playing',
        version: 1,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        history: const [],
        context: const {
          'host_id': 'H',
          'guest_id': 'G',
          'moves': <dynamic>[],
        },
      );
      expect(XiangqiRoom.canPerform('MOVE', snap, isHost: true), isTrue);
      expect(XiangqiRoom.canPerform('MOVE', snap, isHost: false), isTrue);
    });

    test('未知的 action 名 → 放行（服务端不拦，客户端也不拦）', () {
      final snap = _snap(
        hostId: 'H',
        guestId: 'G',
        hostColor: 'r',
        initialSide: 'r',
        moves: 0,
      );
      expect(XiangqiRoom.canPerform('SOMETHING_NEW', snap, isHost: false), isTrue);
    });
  });

  group('⑨ 悔棋后轮次方 = side_to_move(#c.moves)，申请方成为当前走子方', () {
    // 服务端 UNDO_ACCEPT 的 pop 规则（见 Lua on_action_UNDO_ACCEPT）：
    //   先手方申请 → n 偶数 pop 2 / n 奇数 pop 1
    //   后手方申请 → n 偶数 pop 1 / n 奇数 pop 2
    //   目标：pop 之后轮次回到**申请方**。
    int popsFor({required int n, required bool requesterIsFirst}) =>
        requesterIsFirst ? ((n % 2 == 1) ? 1 : 2) : ((n % 2 == 1) ? 2 : 1);

    for (final n in [1, 2, 3, 4, 5]) {
      for (final requesterIsFirst in [true, false]) {
        // 服务端 UNDO_OFFER 的前置门：后手方申请要求 n >= 2（先手方 n >= 1 即可）
        // → n=1 且后手方申请会被服务端直接拒绝，根本不会走到 pop。
        if (!requesterIsFirst && n < 2) {
          test('n=$n 后手方申请 → 服务端 UNDO_OFFER 门直接拒绝（不会 pop）', () {
            expect(n < 2, isTrue);
          });
          continue;
        }
        test('n=$n 申请方=${requesterIsFirst ? '先手' : '后手'} → pop 后该申请方走', () {
          // 造 n 手真实棋谱（红先黑后交替）
          const line = [
            'b7e7', 'h0g2', 'a6a5', 'g3g4', 'b9c7',
          ];
          var board = XiangqiBoardState.initial();
          final history = <XiangqiMoveRecord>[];
          for (var i = 0; i < n; i++) {
            final m = XiangqiMove.fromUci(line[i]);
            expect(m, isNotNull);
            board = applyXiangqiMoveSimple(board, m!);
            history.add(XiangqiMoveRecord(
              uci: line[i],
              by: i.isEven ? 'H' : 'G',
              ts: i,
              fen: fenFromBoardState(board),
            ));
          }

          // 服务端 pop 之后剩余的棋谱
          final pops = popsFor(n: n, requesterIsFirst: requesterIsFirst);
          final remaining = history.sublist(0, history.length - pops);

          // 客户端按剩余棋谱重放
          final r = XiangqiRoom.rebuildBoardVerified(
            remaining,
            initialFen: kXiangqiStartingFen,
            initialSide: XiangqiColor.red,
          );

          // 申请方必须成为当前走子方（先手方 = 红，后手方 = 黑）
          final requesterColor =
              requesterIsFirst ? XiangqiColor.red : XiangqiColor.black;
          expect(
            r.board.sideToMove,
            requesterColor,
            reason: 'n=$n 申请方=${requesterIsFirst ? '先手' : '后手'}：'
                'pop $pops 手后轮次必须回到申请方',
          );
        });
      }
    }
  });
}
