import 'dart:math';
import '../../surround_game_constants.dart';

/// 碰撞检测工具 — 纯函数
class CollisionDetector {
  CollisionDetector._();

  /// 检测指定位置是否碰撞（边界或轨迹）
  static bool wouldCollide(List<List<CellState>> board, Point<int> pos) {
    final rows = board.length;
    final cols = board[0].length;

    // 超出边界
    if (pos.x < 0 || pos.x >= rows || pos.y < 0 || pos.y >= cols) {
      return true;
    }

    // 撞墙或撞轨迹
    final cell = board[pos.x][pos.y];
    return cell == CellState.wall ||
        cell == CellState.hostTrail ||
        cell == CellState.clientTrail;
  }

  /// 检测玩家是否无路可走
  static bool hasNoValidMoves(List<List<CellState>> board, Point<int> pos) {
    return getValidMoves(board, pos).isEmpty;
  }

  /// 获取指定位置周围可用的方向
  static List<Direction> getValidMoves(
    List<List<CellState>> board,
    Point<int> pos,
  ) {
    final moves = <Direction>[];

    for (final dir in Direction.values) {
      final next = _moveInDirection(pos, dir);
      if (!wouldCollide(board, next)) {
        moves.add(dir);
      }
    }

    return moves;
  }

  /// 按方向计算下一个位置
  static Point<int> _moveInDirection(Point<int> pos, Direction dir) {
    switch (dir) {
      case Direction.up:
        return Point<int>(pos.x - 1, pos.y);
      case Direction.down:
        return Point<int>(pos.x + 1, pos.y);
      case Direction.left:
        return Point<int>(pos.x, pos.y - 1);
      case Direction.right:
        return Point<int>(pos.x, pos.y + 1);
    }
  }
}
