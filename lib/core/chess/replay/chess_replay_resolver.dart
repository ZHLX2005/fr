// lib/core/chess/replay/chess_replay_resolver.dart
//
// 棋谱重演纯函数 —— initialFen + UCI 整局谱 → (moves, states) 局面子序列。
//
// 逻辑与 ChessRoomPage._enterReplay 的重演段一致（防御语义相同）：
//   · 每手 UCI 先 Move.fromUci，再与当前局面合法走法逐字段匹配
//     （from/to/promotion）—— 匹配到的 Move 自带正确 flag（易位 / 吃过路兵 /
//     升变），applyMove 依赖 flag 才能正确搬车 / 移除过路兵；裸 fromUci 的
//     走法会把王车易位走成"王飞两格、车不动"。
//   · 畸形 uci / 棋谱与局面脱节 → 防御截断：只保留匹配成功的前缀，
//     parsedCount < uciMoves.length（调用方 UI 可提示"谱尾 N 手无法解析"）。
//   · initialFen 解析失败 → 回退标准开局（防御）。

import '../engine/chess_engine.dart';
import '../engine/fen_codec.dart';
import '../engine/make_move.dart';
import '../models/board_state.dart';
import '../models/move.dart';

/// 重演结果：局面子序列（states.length = moves.length + 1，含初始局面）。
class ChessReplayResult {
  /// 成功重演的走法（带正确 flag）。
  final List<Move> moves;

  /// 局面子序列：states[0] = 初始局面，states[i] = 第 i 手之后。
  final List<BoardState> states;

  /// 原始谱手数（uciMoves.length）—— 与 moves.length 之差 = 截断手数。
  final int requestedCount;

  const ChessReplayResult({
    required this.moves,
    required this.states,
    required this.requestedCount,
  });

  /// 谱尾被截断的手数（0 = 整谱完整重演）。
  int get truncated => requestedCount - moves.length;
}

/// 棋谱重演（纯函数集）。
class ChessGameReplayResolver {
  /// 从 [initialFen] 起按 [uciMoves] 逐手重演。
  static ChessReplayResult resolve({
    required String initialFen,
    required List<String> uciMoves,
    ChessEngine engine = const ChessEngine(),
  }) {
    // 起始局面：解析失败（畸形 FEN）→ 回退标准开局（防御）。
    BoardState start;
    try {
      start = FenCodec.fromFen(initialFen);
    } on Object {
      start = BoardState.initial();
    }

    final moves = <Move>[];
    final states = <BoardState>[start];
    var cur = states.first;
    for (final uci in uciMoves) {
      if (uci.length < 4) break;
      final Move parsed;
      try {
        parsed = Move.fromUci(uci);
      } on ArgumentError {
        break; // 畸形 uci —— 防御：只回放到此之前。
      }
      Move? matched;
      for (final m in engine.generateLegalMoves(cur)) {
        if (m.from == parsed.from &&
            m.to == parsed.to &&
            m.promotion == parsed.promotion) {
          matched = m;
          break;
        }
      }
      if (matched == null) break; // 棋谱与局面脱节 → 截断。
      cur = applyMove(cur, matched).nextState;
      moves.add(matched);
      states.add(cur);
    }
    return ChessReplayResult(
      moves: moves,
      states: states,
      requestedCount: uciMoves.length,
    );
  }
}
