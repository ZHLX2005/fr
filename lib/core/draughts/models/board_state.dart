// lib/core/draughts/models/board_state.dart
//
// 10×10 棋盘不可变状态（immutable value）。
//
// 设计（对齐 lib/core/chess/models/board_state.dart）：
//   · 内部用 `List<int?>` 长度 100 —— null = 空格，否则是 DraughtsPiece.pack()。
//     packing schema 见 models/piece.dart。
//   · 浅色格（(row+col)%2==0）永远为 null —— 棋子只落深色格。
//   · 任何"下一步"通过 copyWith 返回新实例，永不 mutate。
//   · FEN 起点在 pdn_codec 中实现，不在此耦合。

import '../constants/draughts_constants.dart';
import 'piece.dart';

/// 不可变棋盘状态。
class DraughtsBoardState {
  final List<int?> _cells;

  /// 当前轮次方
  final DraughtsColor sideToMove;

  /// 自上次吃子以来的半回合数（用于王走 25 步和棋等规则）
  final int pliesSinceCapture;

  const DraughtsBoardState._(
    this._cells,
    this.sideToMove,
    this.pliesSinceCapture,
  );

  /// 起始局面（白先）。
  ///
  /// 直接 inline 起始排布，避免 board_state → pdn_codec 循环依赖。
  factory DraughtsBoardState.initial() {
    final cells = List<int?>.filled(kDraughtsCells, null, growable: false);
    for (var square = 1; square <= kDraughtsPlayableSquares; square++) {
      final idx = draughtsIndexFromSquareNumber(square);
      if (idx < 0) continue;
      if (draughtsIsWhiteStartSquare(square)) {
        cells[idx] = DraughtsPiece.whiteMan.pack();
      } else if (draughtsIsBlackStartSquare(square)) {
        cells[idx] = DraughtsPiece.blackMan.pack();
      }
    }
    return DraughtsBoardState._(cells, DraughtsColor.white, 0);
  }

  /// 任意状态构造
  factory DraughtsBoardState({
    required List<int?> cells,
    required DraughtsColor sideToMove,
    int pliesSinceCapture = 0,
  }) {
    assert(cells.length == kDraughtsCells, 'board must be 100 cells');
    return DraughtsBoardState._(
      List<int?>.of(cells),
      sideToMove,
      pliesSinceCapture,
    );
  }

  /// 公开只读视图：100 个 packed slot
  List<int?> get cells => _cells;

  /// 该格是否空
  bool isEmpty(int index) => _cells[index] == null;

  /// 该格是否有子
  bool isOccupied(int index) => _cells[index] != null;

  /// 该格棋子（null = 空）
  DraughtsPiece? pieceAt(int index) => _cells[index] == null
      ? null
      : DraughtsPiece.unpack(_cells[index]!);

  /// 该格颜色（null = 空）
  DraughtsColor? colorAt(int index) => pieceAt(index)?.color;

  /// 遍历所有非空格：(index, piece)
  Iterable<(int, DraughtsPiece)> get occupied sync* {
    for (var i = 0; i < _cells.length; i++) {
      final slot = _cells[i];
      if (slot == null) continue;
      yield (i, DraughtsPiece.unpack(slot));
    }
  }

  /// 某方所有子的格索引
  List<int> squaresOf(DraughtsColor color) {
    final out = <int>[];
    for (final (idx, piece) in occupied) {
      if (piece.color == color) out.add(idx);
    }
    return out;
  }

  /// 某方棋子数
  int countOf(DraughtsColor color) {
    var n = 0;
    for (final (_, piece) in occupied) {
      if (piece.color == color) n++;
    }
    return n;
  }

  /// 不可变更新：返回新 DraughtsBoardState
  DraughtsBoardState copyWith({
    List<int?>? cells,
    DraughtsColor? sideToMove,
    int? pliesSinceCapture,
  }) {
    return DraughtsBoardState(
      cells: cells ?? _cells,
      sideToMove: sideToMove ?? this.sideToMove,
      pliesSinceCapture: pliesSinceCapture ?? this.pliesSinceCapture,
    );
  }

  /// 单一格子替换（不可变）
  DraughtsBoardState putCell(int index, int? packed) {
    final next = List<int?>.of(_cells);
    next[index] = packed;
    return copyWith(cells: next);
  }

  /// 深拷贝
  DraughtsBoardState copy() => DraughtsBoardState(
        cells: List<int?>.of(_cells),
        sideToMove: sideToMove,
        pliesSinceCapture: pliesSinceCapture,
      );

  /// 局面键（用于三次重复检测）：棋盘 + 轮次方。
  ///
  /// 用紧凑字符串编码 —— 100 格每格 2 bit（0 空 / 1 白兵 / 2 黑兵 / 3 王+色）。
  /// 只需唯一性，不需可读性。
  String get positionKey {
    final buf = StringBuffer(sideToMove == DraughtsColor.white ? 'W' : 'B');
    buf.write(':');
    for (var i = 0; i < _cells.length; i++) {
      final slot = _cells[i];
      if (slot == null) continue;
      buf.write(i);
      buf.write(slot);
      buf.write(',');
    }
    return buf.toString();
  }

  // ───────────── hashCode / operator == ─────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DraughtsBoardState) return false;
    if (sideToMove != other.sideToMove) return false;
    if (pliesSinceCapture != other.pliesSinceCapture) return false;
    for (var i = 0; i < _cells.length; i++) {
      if (_cells[i] != other._cells[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var h = Object.hash(sideToMove, pliesSinceCapture);
    for (final c in _cells) {
      h = Object.hash(h, c);
    }
    return h;
  }
}
