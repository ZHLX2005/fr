// lib/core/chess/engine/attack_map.dart
//
// 受攻击格子（attack map）查询：给定 BoardState + 攻击方颜色，返回
// 该颜色能攻击到的所有 1D 格子索引集合。
//
// 用途：
//   1. 将军判定（King 是否在 attackedSquares 中）
//   2. 吃过路兵 / 王车易位 / 其他"该格不能被攻击" 的规则判定
//   3. 合法走法筛选（makeMove 后，自己的王不能落在 attackedSquares 里）
//
// 实现要点：
//   - 不模拟对方王（避免"双方互吃王"的循环），跳过 King 自身。
//   - 兵（pawn）从攻击方视角以"斜前"为攻击位（与移动位不同）
//   - 马走日字（8 个固定偏移）
//   - 象/车/后走直线，受第一子阻挡
//   - 王走 8 邻（不过这里我们也不模拟对方王，故可省略）

import '../models/board_state.dart';
import '../models/piece.dart';

const List<List<int>> kKnightOffsets = [
  [-2, -1], [-2, 1], [-1, -2], [-1, 2],
  [1, -2], [1, 2], [2, -1], [2, 1],
];

const List<List<int>> kKingOffsets = [
  [-1, -1], [-1, 0], [-1, 1],
  [0, -1], [0, 1],
  [1, -1], [1, 0], [1, 1],
];

const List<List<int>> kRookDirs = [
  [-1, 0], [1, 0], [0, -1], [0, 1],
];

const List<List<int>> kBishopDirs = [
  [-1, -1], [-1, 1], [1, -1], [1, 1],
];

const List<List<int>> kQueenDirs = [
  [-1, 0], [1, 0], [0, -1], [0, 1],
  [-1, -1], [-1, 1], [1, -1], [1, 1],
];

/// 计算 [attackColor] 方能攻击到的 1D 格子集合
List<int> computeAttackedSquares(BoardState state, PieceColor attackColor) {
  final attacked = <int>{};

  for (var i = 0; i < state.cells.length; i++) {
    final slot = state.cells[i];
    if (slot == null) continue;
    final type = PieceSlot.unpackType(slot);
    final color = PieceSlot.unpackColorEnum(slot);
    if (color != attackColor) continue;

    final row = i ~/ 8;
    final col = i % 8;

    switch (type) {
      case PieceType.pawn:
        // 兵的攻击是从"对方视角"出发的斜前方
        // 白方 (row 7 白底线) 攻击 row-1 两格
        // 黑方攻击 row+1 两格
        if (attackColor == PieceColor.white) {
          _addPawnAttacks(attacked, row, col, -1);
        } else {
          _addPawnAttacks(attacked, row, col, 1);
        }
        break;
      case PieceType.knight:
        for (final off in kKnightOffsets) {
          final r = row + off[0];
          final c = col + off[1];
          if (_inRange(r, c)) {
            attacked.add(r * 8 + c);
          }
        }
        break;
      case PieceType.bishop:
        _slide(state, attacked, row, col, kBishopDirs);
        break;
      case PieceType.rook:
        _slide(state, attacked, row, col, kRookDirs);
        break;
      case PieceType.queen:
        _slide(state, attacked, row, col, kQueenDirs);
        break;
      case PieceType.king:
        // 不模拟对方王做"被攻击"判定是为了打破循环：
        // 双方 King 永远不会直接相邻，但攻击盘算法只看"几何是否存在阻碍"，故仍枚举 8 邻。
        for (final off in kKingOffsets) {
          final r = row + off[0];
          final c = col + off[1];
          if (_inRange(r, c)) {
            attacked.add(r * 8 + c);
          }
        }
        break;
    }
  }
  return attacked.toList();
}

bool _inRange(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

void _addPawnAttacks(Set<int> attacked, int row, int col, int dirRow) {
  // 兵的斜前方向：dirRow 是当兵的"前进方向"（白 -1、黑 +1）
  final r = row + dirRow;
  // 两个斜列
  for (final dc in [-1, 1]) {
    final c = col + dc;
    if (_inRange(r, c)) {
      attacked.add(r * 8 + c);
    }
  }
}

void _slide(
  BoardState state,
  Set<int> attacked,
  int row,
  int col,
  List<List<int>> directions,
) {
  for (final d in directions) {
    var r = row;
    var c = col;
    while (true) {
      r += d[0];
      c += d[1];
      if (!_inRange(r, c)) break;
      final idx = r * 8 + c;
      attacked.add(idx);
      final slot = state.cells[idx];
      if (slot != null) break; // 第一个子阻挡（含对方子也算"被攻击"）
    }
  }
}
