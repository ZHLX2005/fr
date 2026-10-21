// lib/core/xiangqi/engine/move_generator.dart
//
// 中国象棋走法生成 + 将军判定。
//
// ## 规则要点（七子各一条）
//
//   · 将/帅  九宫内直行一格 —— 另有「将帅照面」：双将同列且中间无子 → 非法局面。
//   · 士      九宫内斜行一格。
//   · 象/相   走田（斜二格），**不过河**，中点有子则「塞象眼」不可走。
//   · 马      走日（斜一横二），相邻正交方向有子则「蹩马腿」不可走。
//   · 车      直线滑行，遇子即止（可吃第一个对方子）。
//   · 炮      不吃子时同车；吃子必须隔且仅隔一子（炮架）后吃到第一个对方子。
//   · 卒/兵   只进不退；过河后可左右横走（不可后退）。
//
// ## 与国际象棋 / 国际跳棋的差异
//
//   · 无升变 / 无吃过路兵 / 无易位。
//   · 「将军」是**局面合法性**的一部分：走子方必须保证自己将不被攻击
//     （含将帅照面），因此合法性过滤 = 走后自己将不被攻击。
//   · 困毙（未被将军但无着可走）在 status 判定里判负，不是和棋。
//
// ## 走法合法性分两层
//
//   1. 伪合法（pseudo-legal）：只看本棋种规则，不看自己将是否被攻击。
//   2. 合法（legal）：伪合法走法**走后**自己将不被攻击。
//
// 引擎对外只暴露合法走法（legalMoves）；伪合法仅内部使用。

import '../constants/xiangqi_constants.dart';
import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';

/// 马的 8 个走法：(dr, dc)
///
/// 蹩马腿规则在 [xiangqiHorseAttacks] / 走法生成里按需计算。
const List<(int, int)> kXiangqiHorseMoves = [
  (-2, -1), (-2, 1),
  (2, -1), (2, 1),
  (-1, -2), (1, -2),
  (-1, 2), (1, 2),
];

/// 象的 4 个走法：(dr, dc) —— 斜二格
const List<(int, int)> kXiangqiElephantMoves = [
  (-2, -2), (-2, 2), (2, -2), (2, 2),
];

/// 将/帅的 4 个走法：(dr, dc) —— 直行一格
const List<(int, int)> kXiangqiGeneralMoves = [
  (-1, 0), (1, 0), (0, -1), (0, 1),
];

/// 士的 4 个走法：(dr, dc) —— 斜行一格
const List<(int, int)> kXiangqiAdvisorMoves = [
  (-1, -1), (-1, 1), (1, -1), (1, 1),
];

/// 兵的 4 个走法：(dr, dc) —— 前 / 左 / 右（后退不在列）
const List<(int, int)> kXiangqiPawnMoves = [
  (-1, 0), (0, -1), (0, 1),
];

/// 滑行类（车 / 炮）的 4 个方向
const List<(int, int)> kXiangqiSlideDirs = [
  (-1, 0), (1, 0), (0, -1), (0, 1),
];

/// 马腿（蹩马腿）所在格：走日 (dr, dc) 时的相邻正交格。
///
/// |dr| == 2 → 腿在 (r + dr/2, c)；|dc| == 2 → 腿在 (r, c + dc/2)。
(int, int) xiangqiHorseLeg(int row, int col, int dr, int dc) {
  if (dr.abs() == 2) return (row + dr ~/ 2, col);
  return (row, col + dc ~/ 2);
}

/// 该格是否被 [byColor] 的棋子攻击。
///
/// 「将军」= 对方将/帅所在格被攻击；另含**将帅照面**：
/// 双方将同列且中间无子时，双方互相视为被攻击（该局面非法）。
bool xiangqiIsSquareAttacked(
  XiangqiBoardState board,
  int target,
  XiangqiColor byColor,
) {
  for (final (idx, piece) in board.occupied) {
    if (piece.color != byColor) continue;
    if (xiangqiPieceAttacks(board, idx, piece, target)) return true;
  }
  return false;
}

/// 单个棋子 [piece]（位于 [from]）是否攻击 [target]。
bool xiangqiPieceAttacks(
  XiangqiBoardState board,
  int from,
  XiangqiPiece piece,
  int target,
) {
  if (from == target) return false;
  final fr = xiangqiRowOf(from);
  final fc = xiangqiColOf(from);
  final tr = xiangqiRowOf(target);
  final tc = xiangqiColOf(target);

  switch (piece.type) {
    case XiangqiPieceType.chariot:
      return xiangqiSlidesUnobstructed(board, fr, fc, tr, tc);

    case XiangqiPieceType.cannon:
      return xiangqiCannonAttacks(board, fr, fc, tr, tc);

    case XiangqiPieceType.horse:
      return xiangqiHorseAttacks(board, fr, fc, tr, tc);

    case XiangqiPieceType.pawn:
      return xiangqiPawnAttacks(board, fr, fc, tr, tc, piece.isRed);

    case XiangqiPieceType.advisor:
      if ((tr - fr).abs() != 1 || (tc - fc).abs() != 1) return false;
      return xiangqiInPalaceOf(tr, tc, isRed: piece.isRed);

    case XiangqiPieceType.elephant:
      if ((tr - fr).abs() != 2 || (tc - fc).abs() != 2) return false;
      // 不过河：起点与终点必须同属一个半场（与棋子颜色无关）
      if (xiangqiHalfOf(tr) != xiangqiHalfOf(fr)) return false;
      // 塞象眼：象眼（中点）有子则不可走
      final midR = (fr + tr) ~/ 2;
      final midC = (fc + tc) ~/ 2;
      return board.isEmpty(xiangqiIndex(midR, midC));

    case XiangqiPieceType.general:
      // 将帅照面：同列且中间无子 → 攻击。
      // ⚠ 这里「攻击」的是**整条纵线**而非某个具体子 —— 这正是「将帅照面」
      //   规则的正确表达：走完任何一手后，若双将同列相望，该方将被判「被将军」，
      //   该着法随之被判非法（不限于移动将/帅本人，任何棋子让开纵线都算）。
      //   若 [xiangqiIsSquareAttacked] 被用于「受攻击格」类 UI，需注意此语义。
      if (fc == tc && xiangqiSlidesUnobstructed(board, fr, fc, tr, tc)) {
        return true;
      }
      // 九宫内直行一格
      if ((tr - fr).abs() + (tc - fc).abs() != 1) return false;
      return xiangqiInPalaceOf(tr, tc, isRed: piece.isRed);
  }
}

/// 车式滑行：同直线且中间无子。
bool xiangqiSlidesUnobstructed(
  XiangqiBoardState board,
  int fr,
  int fc,
  int tr,
  int tc,
) {
  if (fr != tr && fc != tc) return false;
  final dr = tr - fr;
  final dc = tc - fc;
  final stepR = dr == 0 ? 0 : (dr > 0 ? 1 : -1);
  final stepC = dc == 0 ? 0 : (dc > 0 ? 1 : -1);
  var r = fr + stepR;
  var c = fc + stepC;
  while (r != tr || c != tc) {
    if (!board.isEmpty(xiangqiIndex(r, c))) return false;
    r += stepR;
    c += stepC;
  }
  return true;
}

/// 炮式攻击：同直线，中间**恰好一个**子。
bool xiangqiCannonAttacks(
  XiangqiBoardState board,
  int fr,
  int fc,
  int tr,
  int tc,
) {
  if (fr != tr && fc != tc) return false;
  final dr = tr - fr;
  final dc = tc - fc;
  final stepR = dr == 0 ? 0 : (dr > 0 ? 1 : -1);
  final stepC = dc == 0 ? 0 : (dc > 0 ? 1 : -1);
  var r = fr + stepR;
  var c = fc + stepC;
  var screens = 0;
  while (r != tr || c != tc) {
    if (!board.isEmpty(xiangqiIndex(r, c))) {
      screens++;
      if (screens > 1) return false;
    }
    r += stepR;
    c += stepC;
  }
  return screens == 1;
}

/// 马式攻击：走日 + 腿未被蹩。
bool xiangqiHorseAttacks(
  XiangqiBoardState board,
  int fr,
  int fc,
  int tr,
  int tc,
) {
  final dr = tr - fr;
  final dc = tc - fc;
  final isHorseShape = (dr.abs() == 2 && dc.abs() == 1) ||
      (dr.abs() == 1 && dc.abs() == 2);
  if (!isHorseShape) return false;
  final (legR, legC) = xiangqiHorseLeg(fr, fc, dr, dc);
  if (!xiangqiOnBoard(legR, legC)) return false;
  return board.isEmpty(xiangqiIndex(legR, legC));
}

/// 兵/卒攻击：向前一格；过河后还能左右横走。
bool xiangqiPawnAttacks(
  XiangqiBoardState board,
  int fr,
  int fc,
  int tr,
  int tc,
  bool isRed,
) {
  final forward = isRed ? -1 : 1;
  if (tr - fr == forward && tc == fc) return true;
  // 过河后可横走（不可后退）
  if (tr == fr && (tc - fc).abs() == 1 &&
      xiangqiCrossedRiver(fr, isRed: isRed)) {
    return true;
  }
  return false;
}

/// 伪合法走法（不看自己将是否被攻击）。
List<XiangqiMove> xiangqiPseudoLegalMoves(XiangqiBoardState board) {
  final side = board.sideToMove;
  final out = <XiangqiMove>[];
  for (final (idx, piece) in board.occupied) {
    if (piece.color != side) continue;
    _collectPieceMoves(board, idx, piece, out);
  }
  return out;
}

/// 单个棋子的伪合法走法。
void _collectPieceMoves(
  XiangqiBoardState board,
  int idx,
  XiangqiPiece piece,
  List<XiangqiMove> out,
) {
  final r = xiangqiRowOf(idx);
  final c = xiangqiColOf(idx);

  void add(int tr, int tc) {
    if (!xiangqiOnBoard(tr, tc)) return;
    final to = xiangqiIndex(tr, tc);
    final target = board.pieceAt(to);
    if (target != null) {
      // 不能吃自己的子
      if (target.color == piece.color) return;
      // 不允许吃将 —— 对局以将死/困毙结束，不是吃光对方将
      if (target.isGeneral) return;
    }
    out.add(XiangqiMove(from: idx, to: to, captured: target));
  }

  switch (piece.type) {
    case XiangqiPieceType.general:
      for (final (dr, dc) in kXiangqiGeneralMoves) {
        final tr = r + dr;
        final tc = c + dc;
        if (!xiangqiInPalaceOf(tr, tc, isRed: piece.isRed)) continue;
        add(tr, tc);
      }

    case XiangqiPieceType.advisor:
      for (final (dr, dc) in kXiangqiAdvisorMoves) {
        final tr = r + dr;
        final tc = c + dc;
        if (!xiangqiInPalaceOf(tr, tc, isRed: piece.isRed)) continue;
        add(tr, tc);
      }

    case XiangqiPieceType.elephant:
      for (final (dr, dc) in kXiangqiElephantMoves) {
        final tr = r + dr;
        final tc = c + dc;
        // 目标越界 → 跳过（同时保证象眼中点在界内）
        if (!xiangqiOnBoard(tr, tc)) continue;
        // 不过河：起点与终点必须同属一个半场（与棋子颜色无关）
        if (xiangqiHalfOf(tr) != xiangqiHalfOf(r)) continue;
        // 塞象眼
        final midR = r + dr ~/ 2;
        final midC = c + dc ~/ 2;
        if (!board.isEmpty(xiangqiIndex(midR, midC))) continue;
        add(tr, tc);
      }

    case XiangqiPieceType.horse:
      for (final (dr, dc) in kXiangqiHorseMoves) {
        final tr = r + dr;
        final tc = c + dc;
        // 目标越界 → 跳过（同时保证马腿格也在界内）
        if (!xiangqiOnBoard(tr, tc)) continue;
        final (legR, legC) = xiangqiHorseLeg(r, c, dr, dc);
        if (!board.isEmpty(xiangqiIndex(legR, legC))) continue; // 蹩马腿
        add(tr, tc);
      }

    case XiangqiPieceType.chariot:
      for (final (dr, dc) in kXiangqiSlideDirs) {
        var tr = r + dr;
        var tc = c + dc;
        while (xiangqiOnBoard(tr, tc)) {
          final to = xiangqiIndex(tr, tc);
          final target = board.pieceAt(to);
          if (target == null) {
            out.add(XiangqiMove(from: idx, to: to));
          } else {
            if (target.color != piece.color && !target.isGeneral) {
              out.add(XiangqiMove(from: idx, to: to, captured: target));
            }
            break; // 遇子即止
          }
          tr += dr;
          tc += dc;
        }
      }

    case XiangqiPieceType.cannon:
      for (final (dr, dc) in kXiangqiSlideDirs) {
        var tr = r + dr;
        var tc = c + dc;
        // ① 不吃子段：遇第一个子之前都可走（空点）
        var sawScreen = false;
        while (xiangqiOnBoard(tr, tc)) {
          final to = xiangqiIndex(tr, tc);
          final target = board.pieceAt(to);
          if (!sawScreen) {
            if (target == null) {
              out.add(XiangqiMove(from: idx, to: to));
            } else {
              sawScreen = true; // 炮架
            }
          } else {
            // ② 吃子段：越过炮架后遇到的第一个对方子可吃
            if (target != null) {
              if (target.color != piece.color && !target.isGeneral) {
                out.add(XiangqiMove(from: idx, to: to, captured: target));
              }
              break;
            }
          }
          tr += dr;
          tc += dc;
        }
      }

    case XiangqiPieceType.pawn:
      final forward = piece.forwardDelta;
      // ① 前进一格（永远可以）
      add(r + forward, c);
      // ② 过河后可左右横走（不可后退）
      if (xiangqiCrossedRiver(r, isRed: piece.isRed)) {
        add(r, c - 1);
        add(r, c + 1);
      }
  }
}

/// 该方是否被将军（含将帅照面）。
///
/// 该方没有将/帅（非法局面）时返回 false —— 「被将军」的前提是有将可被攻击；
/// 缺将的局面由 `XiangqiEngine.status` 单独判负。
bool xiangqiIsInCheck(XiangqiBoardState board, XiangqiColor color) {
  final general = board.generalSquareOf(color);
  if (general < 0) return false;
  return xiangqiIsSquareAttacked(board, general, xiangqiOpposite(color));
}

/// 合法走法（走后自己将不被攻击）。
List<XiangqiMove> xiangqiLegalMoves(XiangqiBoardState board) {
  final side = board.sideToMove;
  final out = <XiangqiMove>[];
  for (final move in xiangqiPseudoLegalMoves(board)) {
    final next = xiangqiApplyMoveRaw(board, move);
    if (!xiangqiIsInCheck(next, side)) out.add(move);
  }
  return out;
}

/// 某格上的棋子（若属于 [side]）的合法走法。
List<XiangqiMove> xiangqiLegalMovesFrom(
  XiangqiBoardState board,
  int from,
) {
  final side = board.sideToMove;
  final piece = board.pieceAt(from);
  if (piece == null || piece.color != side) return const [];
  final out = <XiangqiMove>[];
  final all = xiangqiPseudoLegalMoves(board);
  for (final move in all) {
    if (move.from != from) continue;
    final next = xiangqiApplyMoveRaw(board, move);
    if (!xiangqiIsInCheck(next, side)) out.add(move);
  }
  return out;
}

/// 原始走子（不做合法性检查）—— 内部用，供合法性过滤与终局判定。
///
/// 放在本文件避免与 make_move.dart 形成循环依赖。
XiangqiBoardState xiangqiApplyMoveRaw(
  XiangqiBoardState board,
  XiangqiMove move,
) {
  final cells = List<int?>.of(board.cells);
  cells[move.from] = null;
  cells[move.to] = board.cells[move.from];
  return XiangqiBoardState(
    cells: cells,
    sideToMove: xiangqiOpposite(board.sideToMove),
  );
}
