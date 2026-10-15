// lib/core/draughts/engine/make_move.dart
//
// 应用走法到棋盘，返回新状态（不可变）。
//
// 与国际象棋 make_move 的差异：
//   · 无易位 / 无吃过路兵 / 无需撤销（跳棋无"送将"约束 → 无撤销需求）
//   · 吃子可能有多个（整手结束才全部移除）—— 但棋盘只有起点与终点两处变动，
//     中间跳点不落子。
//   · 升王在终点判定（move.isPromotion 由 move_generator 算好）。

import '../constants/draughts_constants.dart';
import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';

/// 应用走法的结果
class DraughtsApplyResult {
  /// 走完后的新棋盘
  final DraughtsBoardState nextState;

  /// 本手被移除的棋子（颜色按被吃方）—— 供 UI 吃子动画 / 棋谱用
  final List<int> capturedSquares;

  const DraughtsApplyResult(this.nextState, this.capturedSquares);
}

/// 应用 [move] 到 [state]，返回新状态。
///
/// 非法走法（起点无子 / 起终点不合法）会抛 [ArgumentError] —— 调用方应先经
/// [generateMoves] 拿合法走法。
DraughtsApplyResult applyMove(DraughtsBoardState state, DraughtsMove move) {
  final movingSlot = state.cells[move.from];
  if (movingSlot == null) {
    throw ArgumentError('No piece at from square ${move.from}');
  }
  final piece = DraughtsPiece.unpack(movingSlot);

  if (draughtsSquareNumberOfIndex(move.to) < 0) {
    throw ArgumentError('Illegal destination (light square) ${move.to}');
  }

  final next = List<int?>.of(state.cells);

  // 1) 移走原格
  next[move.from] = null;

  // 2) 落子（必要时升王）
  final landed = move.isPromotion ? piece.promote() : piece;
  next[move.to] = landed.pack();

  // 3) 移除全部被吃子（整手结束时）
  for (final cap in move.capturedSquares) {
    next[cap] = null;
  }

  final newState = state.copyWith(
    cells: next,
    sideToMove: draughtsOpposite(state.sideToMove),
    pliesSinceCapture:
        move.isCapture ? 0 : state.pliesSinceCapture + 1,
  );

  return DraughtsApplyResult(newState, move.capturedSquares);
}

/// 便利：只取新状态
DraughtsBoardState applyMoveSimple(DraughtsBoardState state, DraughtsMove move) =>
    applyMove(state, move).nextState;
