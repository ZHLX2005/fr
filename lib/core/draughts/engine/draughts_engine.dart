// lib/core/draughts/engine/draughts_engine.dart
//
// 国际跳棋引擎对外 facade：
//   · legalMoves(state)      → 合法着法（含强制吃子 + 最长吃子裁决）
//   · applyMove(state, move) → 新状态
//   · status(state, [history]) → 终局判定
//
// 设计（对齐 lib/core/chess/engine/chess_engine.dart）：
//   · 跳棋没有"送将"约束 → 走了就是合法，无需二次筛查（比国际象棋简单）。
//   · 终局几何：对方无子 / 无着法 / 王对王 / 三次重复。
//   · 性能：走法生成 O(子数 × 链分支)，10×10 完全够用；不追求搜索性能。

import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import 'make_move.dart';
import 'move_generator.dart';

/// 跳棋引擎对外接口
class DraughtsEngine {
  const DraughtsEngine();

  /// [state.sideToMove] 的全部合法着法。
  ///
  /// 有吃子则只返回最长吃子链（强制吃子 + 最长吃子规则）。
  List<DraughtsMove> legalMoves(DraughtsBoardState state) =>
      generateMoves(state);

  /// 应用走法
  DraughtsApplyResult apply(DraughtsBoardState state, DraughtsMove move) =>
      applyMove(state, move);

  /// 是否还有合法着法
  bool hasLegalMoves(DraughtsBoardState state) =>
      generateMoves(state).isNotEmpty;

  /// 终局判定。
  ///
  /// [positionHistory] 传该局**至今**所有局面的 `positionKey`（含当前），
  /// 用于三次重复检测；不传则跳过重复检测。
  DraughtsStatus status(
    DraughtsBoardState state, {
    List<String> positionHistory = const [],
  }) {
    final me = state.sideToMove;
    final opp = draughtsOpposite(me);

    // 1) 对方已无子 → 我方胜
    if (state.countOf(opp) == 0) {
      return DraughtsStatus(
        me == DraughtsColor.white
            ? DraughtsOutcome.whiteWins
            : DraughtsOutcome.blackWins,
        DraughtsEndReason.noPieces,
      );
    }

    // 2) 王对王（双方各只剩 1 个王）→ 和
    if (_isKingVsKing(state)) {
      return const DraughtsStatus(
        DraughtsOutcome.draw,
        DraughtsEndReason.kingVsKing,
      );
    }

    // 3) 三次重复局面 → 和
    if (positionHistory.isNotEmpty &&
        _isThreefold(positionHistory, state.positionKey)) {
      return const DraughtsStatus(
        DraughtsOutcome.draw,
        DraughtsEndReason.threefoldRepetition,
      );
    }

    // 4) 无着法 → 对方胜（跳棋不同于国际象棋：堵死判负，不是和棋）
    if (generateMoves(state).isEmpty) {
      return DraughtsStatus(
        opp == DraughtsColor.white
            ? DraughtsOutcome.whiteWins
            : DraughtsOutcome.blackWins,
        DraughtsEndReason.noMoves,
      );
    }

    return DraughtsStatus.playing;
  }

  /// 便利：apply + 检查终局（返回新状态与走后的状态值）
  (DraughtsBoardState, DraughtsStatus) applyAndCheck(
    DraughtsBoardState state,
    DraughtsMove move, {
    List<String> positionHistory = const [],
  }) {
    final next = applyMove(state, move).nextState;
    return (next, status(next, positionHistory: positionHistory));
  }

  bool _isKingVsKing(DraughtsBoardState state) {
    if (state.countOf(DraughtsColor.white) != 1) return false;
    if (state.countOf(DraughtsColor.black) != 1) return false;
    for (final (_, piece) in state.occupied) {
      if (!piece.isKing) return false;
    }
    return true;
  }

  bool _isThreefold(List<String> history, String currentKey) {
    var count = 0;
    for (final k in history) {
      if (k == currentKey) count++;
    }
    return count >= 3;
  }
}

/// 全局默认引擎
const DraughtsEngine kDefaultDraughtsEngine = DraughtsEngine();
