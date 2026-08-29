// lib/core/chess/engine/move_generator.dart
//
// 走法生成器：从 BoardState 生成所有"伪合法"走法（含王车易位 / 吃过路兵 / 升变）
// "伪合法"= 符合几何 + 不留"该格无子（除目标外）" 规则，但尚未校验
// "对方王被将军"是否成立。
//
// 合法走法筛选（剔除"送将" 的走法）由 chess_engine.dart 负责。

import '../models/board_state.dart';
import '../models/move.dart';
import '../models/piece.dart';
import 'attack_map.dart';

/// 生成 [state] 中轮次方（sideToMove）的所有伪合法走法
///
/// 返回 `List<Move>`，按 from asc → to asc 排序（与 generated 通过 minus 走法一次）
List<Move> generatePseudoLegalMoves(BoardState state) {
  final moves = <Move>[];
  final color = state.sideToMove;

  for (var i = 0; i < state.cells.length; i++) {
    final slot = state.cells[i];
    if (slot == null) continue;
    final type = PieceSlot.unpackType(slot);
    final c = PieceSlot.unpackColorEnum(slot);
    if (c != color) continue;

    final row = i ~/ 8;
    final col = i % 8;
    final idx = i;

    switch (type) {
      case PieceType.pawn:
        _generatePawnMoves(state, row, col, color, idx, moves);
        break;
      case PieceType.knight:
        _generateKnightMoves(state, row, col, color, idx, moves);
        break;
      case PieceType.bishop:
        _generateSlidingMoves(state, row, col, color, idx, kBishopDirs, moves);
        break;
      case PieceType.rook:
        _generateSlidingMoves(state, row, col, color, idx, kRookDirs, moves);
        break;
      case PieceType.queen:
        _generateSlidingMoves(state, row, col, color, idx, kQueenDirs, moves);
        break;
      case PieceType.king:
        _generateKingMoves(state, row, col, color, idx, moves);
        break;
    }
  }

  // 排序：先按 from 后按 to，方便测试断言和 P2P 同步
  moves.sort((a, b) {
    final af = a.from * 64 + a.to;
    final bf = b.from * 64 + b.to;
    return af.compareTo(bf);
  });
  return moves;
}

void _generatePawnMoves(
  BoardState state,
  int row,
  int col,
  PieceColor color,
  int idx,
  List<Move> out,
) {
  // 白方前进是 row - 1，黑方是 row + 1
  final dir = color == PieceColor.white ? -1 : 1;
  final startRow = color == PieceColor.white ? 6 : 1;
  final promoRow = color == PieceColor.white ? 0 : 7;

  // 单格前进
  final r1 = row + dir;
  if (_inRange(r1, col) && state.isEmpty(r1 * 8 + col)) {
    if (r1 == promoRow) {
      _addPromotions(out, idx, r1 * 8 + col, color, /*captured*/ null);
    } else {
      out.add(Move(from: idx, to: r1 * 8 + col));
      // 双格前进（仅首步）
      if (row == startRow) {
        final r2 = row + 2 * dir;
        if (_inRange(r2, col) && state.isEmpty(r2 * 8 + col)) {
          out.add(Move(from: idx, to: r2 * 8 + col));
        }
      }
    }
  }

  // 吃子（两斜前，含吃过路兵判定）
  for (final dc in [-1, 1]) {
    final nr = row + dir;
    final nc = col + dc;
    if (!_inRange(nr, nc)) continue;
    final nIdx = nr * 8 + nc;
    final slot = state.cells[nIdx];
    if (slot != null) {
      // 正常吃子（含替换为对方的子）
      if (PieceSlot.unpackColorEnum(slot) != color) {
        if (nr == promoRow) {
          _addPromotions(out, idx, nIdx, color, nIdx);
        } else {
          out.add(Move(
            from: idx,
            to: nIdx,
            capturedSquare: nIdx,
          ));
        }
      }
    } else {
      // 空格子 → 可能是吃过路兵（en passant）
      if (state.enPassantTarget == nIdx) {
        final epVictimIdx = row * 8 + nc; // 同行 nc 列
        out.add(Move(
          from: idx,
          to: nIdx,
          flag: MoveFlags.enPassant,
          capturedSquare: epVictimIdx,
        ));
      }
    }
  }
}

void _addPromotions(
  List<Move> out,
  int fromIdx,
  int toIdx,
  PieceColor color,
  int? capturedSquare,
) {
  // 升变不能是王或兵
  const types = [
    PieceType.queen,
    PieceType.rook,
    PieceType.bishop,
    PieceType.knight,
  ];
  for (final t in types) {
    out.add(Move(
      from: fromIdx,
      to: toIdx,
      promotion: t,
      capturedSquare: capturedSquare,
    ));
  }
}

void _generateKnightMoves(
  BoardState state,
  int row,
  int col,
  PieceColor color,
  int idx,
  List<Move> out,
) {
  for (final off in kKnightOffsets) {
    final r = row + off[0];
    final c = col + off[1];
    if (!_inRange(r, c)) continue;
    final nIdx = r * 8 + c;
    final slot = state.cells[nIdx];
    if (slot == null) {
      out.add(Move(from: idx, to: nIdx));
    } else if (PieceSlot.unpackColorEnum(slot) != color) {
      out.add(Move(
        from: idx,
        to: nIdx,
        capturedSquare: nIdx,
      ));
    }
  }
}

void _generateSlidingMoves(
  BoardState state,
  int row,
  int col,
  PieceColor color,
  int idx,
  List<List<int>> directions,
  List<Move> out,
) {
  for (final d in directions) {
    var r = row;
    var c = col;
    while (true) {
      r += d[0];
      c += d[1];
      if (!_inRange(r, c)) break;
      final nIdx = r * 8 + c;
      final slot = state.cells[nIdx];
      if (slot == null) {
        out.add(Move(from: idx, to: nIdx));
      } else {
        if (PieceSlot.unpackColorEnum(slot) != color) {
          out.add(Move(
            from: idx,
            to: nIdx,
            capturedSquare: nIdx,
          ));
        }
        break;
      }
    }
  }
}

void _generateKingMoves(
  BoardState state,
  int row,
  int col,
  PieceColor color,
  int idx,
  List<Move> out,
) {
  // 8 邻
  for (final off in kKingOffsets) {
    final r = row + off[0];
    final c = col + off[1];
    if (!_inRange(r, c)) continue;
    final nIdx = r * 8 + c;
    final slot = state.cells[nIdx];
    if (slot == null) {
      out.add(Move(from: idx, to: nIdx));
    } else if (PieceSlot.unpackColorEnum(slot) != color) {
      out.add(Move(
        from: idx,
        to: nIdx,
        capturedSquare: nIdx,
      ));
    }
  }

  // 王车易位（Castling）
  // 规则：
  //   1. 双方没有易位权（FEN 中相应位 = true）
  //   2. 王与车之间所有格子都空着
  //   3. 王不在将军状态
  //   4. 王经过的格子（包括自身）都不能在对方攻击范围内
  // 第 4 条由 chess_engine 在合法走法筛选时再次校验（因为这是动态攻击集），
  // 此处只生成"候选"易位；过滤交给上层。
  final attacked = computeAttackedSquares(state, opposite(color));
  final kingColorInCheck = attacked.contains(idx);

  if (color == PieceColor.white) {
    // 白方短易位（王翼）：King e1 (idx 60) → g1 (idx 62)；rook h1 (idx 63)
    if (state.castling.whiteKingSide &&
        state.isEmpty(61) && state.isEmpty(62)) {
      if (!kingColorInCheck &&
          !attacked.contains(61) &&
          !attacked.contains(62)) {
        out.add(Move(
          from: 60,
          to: 62,
          flag: MoveFlags.castling,
        ));
      }
    }
    // 白方长易位（后翼）：King e1 → c1 (idx 58)；rook a1 (idx 56)
    if (state.castling.whiteQueenSide &&
        state.isEmpty(57) && state.isEmpty(58) && state.isEmpty(59)) {
      if (!kingColorInCheck &&
          !attacked.contains(58) &&
          !attacked.contains(59)) {
        out.add(Move(
          from: 60,
          to: 58,
          flag: MoveFlags.castling,
        ));
      }
    }
  } else {
    // 黑方短易位：King e8 (idx 4) → g8 (idx 6)；rook h8 (idx 7)
    if (state.castling.blackKingSide &&
        state.isEmpty(5) && state.isEmpty(6)) {
      if (!kingColorInCheck &&
          !attacked.contains(5) &&
          !attacked.contains(6)) {
        out.add(Move(
          from: 4,
          to: 6,
          flag: MoveFlags.castling,
        ));
      }
    }
    // 黑方长易位：King e8 → c8 (idx 2)；rook a8 (idx 0)
    if (state.castling.blackQueenSide &&
        state.isEmpty(1) && state.isEmpty(2) && state.isEmpty(3)) {
      if (!kingColorInCheck &&
          !attacked.contains(2) &&
          !attacked.contains(3)) {
        out.add(Move(
          from: 4,
          to: 2,
          flag: MoveFlags.castling,
        ));
      }
    }
  }
}

bool _inRange(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;
