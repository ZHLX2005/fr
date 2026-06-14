// Reversi (Othello) 黑白翻转棋 - 核心翻转逻辑（纯 Dart，无 Flutter 依赖）
//
// 规则：双方轮流落子，若新落棋子与己方已有棋子在同一直线（横/竖/斜，共 8 方向）
// 之间夹住了对方一个或多个棋子，则这些被夹住的棋子全部翻转为己方颜色。
// 落子必须至少能翻转一枚对方棋子，否则非法。
//
// 算法参考（已在 .claude/repo 中克隆验证）：
//  - flutterflip/packages/flutterflip_shared/lib/game_board.dart 的 _traversePath（八方向射线扫描）
//  - Othello-game-flutter/lib/models/game_model.dart 的 getFlippedPieces（先收集后翻转）
//
// 本类不可变：所有会改变状态的方法都返回新的 ReversiBoard 实例，
// 便于在历史栈中保存快照实现悔棋。

/// 棋子类型
enum PieceType {
  empty,
  black,
  white;

  /// 对手棋子类型
  PieceType get opponent => switch (this) {
        PieceType.black => PieceType.white,
        PieceType.white => PieceType.black,
        PieceType.empty => PieceType.empty,
      };
}

/// 棋盘坐标（行、列）
class Position {
  final int row;
  final int col;

  const Position(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Position && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => '($row, $col)';
}

/// 不可变的翻转棋棋盘
class ReversiBoard {
  final int size;
  final List<List<PieceType>> _cells;

  const ReversiBoard._(this.size, this._cells);

  /// 标准初始棋盘：中心 4 子（白黑/黑白），黑棋先行由上层状态维护
  factory ReversiBoard.initial({int size = 8}) {
    final cells = List.generate(
      size,
      (_) => List.filled(size, PieceType.empty),
    );
    final m = size ~/ 2;
    cells[m - 1][m - 1] = PieceType.black; // (m-1, m-1) = (3,3) 黑棋
    cells[m - 1][m]     = PieceType.white; // (m-1, m)   = (3,4) 白棋
    cells[m][m - 1]     = PieceType.white; // (m, m-1)   = (4,3) 白棋
    cells[m][m]         = PieceType.black; // (m, m)     = (4,4) 黑棋
    // 标准 Othello：黑棋 d3(3,3) 和 e4(4,4)，白棋 d4(3,4) 和 e3(4,3)，黑方先行
    return ReversiBoard._(size, cells);
  }

  /// 用已有二维数组构造（深拷贝，保证不可变）
  factory ReversiBoard.fromCells(List<List<PieceType>> cells) {
    final size = cells.length;
    final copy = List.generate(
      size,
      (r) => List<PieceType>.from(cells[r]),
    );
    return ReversiBoard._(size, copy);
  }

  /// 获取某格棋子
  PieceType cellAt(int row, int col) => _cells[row][col];

  /// 八方向向量：左上、上、右上、左、右、左下、下、右下
  static const List<List<int>> _directions = [
    [-1, -1],
    [-1, 0],
    [-1, 1],
    [0, -1],
    [0, 1],
    [1, -1],
    [1, 0],
    [1, 1],
  ];

  /// 计算在 [pos] 落 [player] 子后，会被翻转的所有棋子位置
  ///
  /// 沿 8 方向各自扫描：连续遇到对手棋子则收集；若扫描末端是己方棋子
  /// 且收集非空，则该方向收集的棋子全部翻转；若末端是空格或边界则该方向不翻转。
  List<Position> flippableAt(Position pos, PieceType player) {
    if (pos.row < 0 ||
        pos.row >= size ||
        pos.col < 0 ||
        pos.col >= size ||
        _cells[pos.row][pos.col] != PieceType.empty ||
        player == PieceType.empty) {
      return const [];
    }

    final opponent = player.opponent;
    final result = <Position>[];

    for (final d in _directions) {
      final dr = d[0];
      final dc = d[1];
      var r = pos.row + dr;
      var c = pos.col + dc;
      final line = <Position>[];

      // 沿方向连续收集对手棋子
      while (r >= 0 && r < size && c >= 0 && c < size && _cells[r][c] == opponent) {
        line.add(Position(r, c));
        r += dr;
        c += dc;
      }

      // 末端落在己方棋子上 → 这条线有效，全部翻转
      if (line.isNotEmpty &&
          r >= 0 &&
          r < size &&
          c >= 0 &&
          c < size &&
          _cells[r][c] == player) {
        result.addAll(line);
      }
    }

    return result;
  }

  /// 该位置对 [player] 是否为合法落子
  bool isLegalMove(Position pos, PieceType player) =>
      flippableAt(pos, player).isNotEmpty;

  /// 列出 [player] 的所有合法落子位置
  List<Position> legalMovesFor(PieceType player) {
    if (player == PieceType.empty) return const [];
    final moves = <Position>[];
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (_cells[r][c] != PieceType.empty) continue;
        final pos = Position(r, c);
        if (isLegalMove(pos, player)) moves.add(pos);
      }
    }
    return moves;
  }

  /// 落子并翻转，返回新棋盘（不可变）
  ///
  /// 调用前应先用 [isLegalMove] 校验；若非法则原样返回。
  ReversiBoard placeStone(Position pos, PieceType player) {
    final flips = flippableAt(pos, player);
    if (flips.isEmpty) return this;

    final next = List.generate(size, (r) => List<PieceType>.from(_cells[r]));
    next[pos.row][pos.col] = player;
    for (final f in flips) {
      next[f.row][f.col] = player;
    }
    return ReversiBoard._(size, next);
  }

  /// 统计某类棋子数量
  int count(PieceType type) {
    var n = 0;
    for (final row in _cells) {
      for (final cell in row) {
        if (cell == type) n++;
      }
    }
    return n;
  }

  /// 棋盘是否已满
  bool get isFull => count(PieceType.empty) == 0;
}
