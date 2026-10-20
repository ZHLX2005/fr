// test/core/xiangqi/p2p/xiangqi_selfplay_consistency_test.dart
//
// 中国象棋**随机自对弈一致性**测试（property test）。
//
// 用固定种子的伪随机走法，连续走 N 手，每一步校验四条不变量：
//
//   1. **服务端轮次反证成立**：客户端上报的 FEN 轮次位 == 服务端
//      `side_to_move(n+1)`（否则服务端会静默拒绝 MOVE → 走子无效）。
//   2. **重放一致**：服务端存的是「记号 + FEN」，客户端用 `c.moves` 重放
//      出来的局面 == 客户端当步的局面（不一致 → 双端棋盘分叉）。
//   3. **权限表与引擎一致**：`canPerform('MOVE')` == 引擎回合判定
//      （不一致 → 合法玩家被误拦，或该拦的没拦）。
//   4. **不崩**：任一时刻不抛异常（越界 / 索引 / 空引用）。
//
// 固定种子 → 可复现；随机走法 → 覆盖大量真实对局形态（比手写用例广得多）。

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/xiangqi/constants/xiangqi_constants.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/fen_codec.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/make_move.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/move_generator.dart';
import 'package:xiaodouzi_fr/core/xiangqi/engine/xiangqi_engine.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/board_state.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/game_status.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/move.dart';
import 'package:xiaodouzi_fr/core/xiangqi/models/piece.dart';
import 'package:xiaodouzi_fr/core/xiangqi/p2p/xiangqi_room.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot;

/// 服务端 Lua `side_to_move(c, n)` 的 Dart 复刻。
String _luaSideToMove(String initialSide, int n) {
  final first = initialSide.isEmpty ? 'r' : initialSide;
  if (n.isEven) return first;
  return first == 'r' ? 'b' : 'r';
}

Snapshot _snap({
  required int moves,
  required String hostColor,
  required String initialSide,
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
      'host_id': 'H',
      'guest_id': 'G',
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
  test('随机自对弈 200 手：轮次反证 / 重放一致 / 权限表一致 / 不崩', () {
    for (var seed = 0; seed < 8; seed++) {
      final rng = Random(seed);
      var board = XiangqiBoardState.initial();
      final history = <XiangqiMoveRecord>[];

      for (var ply = 0; ply < 200; ply++) {
        final moves = xiangqiLegalMoves(board);

        // ── 不变量 4：终局即停（无着可走 = 将死 / 困毙）──
        if (moves.isEmpty) break;

        // ── 不变量 3：权限表判定 ≡ 引擎回合判定（双方）──
        final snap = _snap(
          moves: history.length,
          hostColor: 'r',
          initialSide: 'r',
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
            reason: 'seed=$seed ply=$ply device=$deviceId —— 权限表与引擎判反',
          );
        }

        // ── 随机走一步 ──
        final move = moves[rng.nextInt(moves.length)];
        final next = applyXiangqiMoveSimple(board, move);

        // ── 不变量 1：服务端轮次反证 ──
        final fen = fenFromBoardState(next);
        final expectTurn = _luaSideToMove('r', history.length + 1);
        expect(
          fen.split(' ')[1],
          expectTurn,
          reason: 'seed=$seed ply=$ply —— 上报 FEN 的轮次位与服务端 '
              'side_to_move(n+1) 不一致 → 服务端会静默拒绝该手',
        );

        history.add(XiangqiMoveRecord(
          uci: move.toUci(),
          by: board.sideToMove == XiangqiColor.red ? 'H' : 'G',
          ts: ply,
          fen: fen,
        ));

        // ── 不变量 2：客户端按 moves 重放 == 走子后的局面 ──
        final replayed = XiangqiRoom.rebuildBoard(history);
        expect(
          replayed,
          next,
          reason: 'seed=$seed ply=$ply —— 客户端重放局面与服务端棋谱分叉',
        );

        board = next;
      }

      // 终局时：引擎必须判出终局，且胜方与「无着可走」的一方相反
      if (xiangqiLegalMoves(board).isEmpty) {
        final st = xiangqiEngineStatus(board);
        expect(st.isOver, isTrue, reason: 'seed=$seed 无着可走却未判终局');
        expect(
          st.winner == XiangqiColorOrNull.red ||
              st.winner == XiangqiColorOrNull.black,
          isTrue,
          reason: 'seed=$seed 困毙/将死必须判负（不是和棋）',
        );
      }
    }
  });

  test('随机自对弈：终局判定与「无着可走」一致（多局）', () {
    for (var seed = 100; seed < 140; seed++) {
      final rng = Random(seed);
      var board = XiangqiBoardState.initial();
      var plies = 0;
      while (plies < 120) {
        final moves = xiangqiLegalMoves(board);
        if (moves.isEmpty) break;
        board = applyXiangqiMoveSimple(board, moves[rng.nextInt(moves.length)]);
        plies++;
      }
      final st = xiangqiEngineStatus(board);
      if (xiangqiLegalMoves(board).isEmpty) {
        expect(st.isOver, isTrue, reason: 'seed=$seed');
        // 将死 = 被将军且无解；困毙 = 未被将军但无解 —— 两者都判负
        final reason = st.reason;
        expect(
          reason == XiangqiEndReason.checkmate ||
              reason == XiangqiEndReason.stalemate,
          isTrue,
          reason: 'seed=$seed 终局原因应为 checkmate / stalemate，实际 $reason',
        );
      } else {
        expect(st.isOver, isFalse, reason: 'seed=$seed 还有着可走却判了终局');
      }
    }
  });
}

/// 引擎终局判定（薄封装，便于在测试里一句话调用）。
XiangqiStatus xiangqiEngineStatus(XiangqiBoardState board) {
  // ignore: avoid_dynamic_calls
  return const XiangqiEngine().status(board);
}
