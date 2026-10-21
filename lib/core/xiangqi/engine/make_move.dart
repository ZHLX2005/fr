// lib/core/xiangqi/engine/make_move.dart
//
// 走法应用 —— 返回新状态（不可变）。
//
// 与国际象棋 make_move 的差异：
//   · 无升变（棋种终身不变）→ 没有 promote 分支。
//   · 无吃过路兵 / 无易位 → 没有额外的 en-passant / castling 状态更新。
//   · 一次走法最多吃一个子（象棋无连锁吃）→ 不需要 capturedSquares 列表。

import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';

/// 应用走法的结果。
class XiangqiApplyResult {
  /// 走完后的新状态
  final XiangqiBoardState nextState;

  /// 本手被吃掉的棋子（null = 未吃子）
  final XiangqiPiece? captured;

  const XiangqiApplyResult(this.nextState, this.captured);
}

/// 应用 [move] 到 [state]，返回新状态。
///
/// 非法走法（起点无子 / 终点有己方子）会抛 [ArgumentError]。
/// 调用方应先用 `xiangqiLegalMoves` 过滤。
XiangqiApplyResult applyXiangqiMove(
  XiangqiBoardState state,
  XiangqiMove move,
) {
  final movingSlot = state.cells[move.from];
  if (movingSlot == null) {
    throw ArgumentError('No piece at from square ${move.from}');
  }
  final piece = XiangqiPiece.unpack(movingSlot);

  final target = state.pieceAt(move.to);
  if (target != null && target.color == piece.color) {
    throw ArgumentError('Destination ${move.to} occupied by own piece');
  }

  final next = List<int?>.of(state.cells);

  // 1) 腾空起点
  next[move.from] = null;

  // 2) 落子（棋种不变，无升变）
  next[move.to] = movingSlot;

  final newState = XiangqiBoardState(
    cells: next,
    sideToMove: xiangqiOpposite(state.sideToMove),
  );

  return XiangqiApplyResult(newState, target);
}

/// 便利：只取新状态。
XiangqiBoardState applyXiangqiMoveSimple(
  XiangqiBoardState state,
  XiangqiMove move,
) =>
    applyXiangqiMove(state, move).nextState;
