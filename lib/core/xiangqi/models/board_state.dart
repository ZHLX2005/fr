// lib/core/xiangqi/models/board_state.dart
//
// 9×10 棋盘不可变状态（immutable value）。
//
// 设计（对齐 lib/core/draughts/models/board_state.dart）：
//   · 内部用 `List<int?>` 长度 90 —— null = 空格，否则是 XiangqiPiece.pack()。
//     packing schema 见 models/piece.dart。
//   · 任何"下一步"通过 copyWith / putCell 返回新实例，永不 mutate。
//   · FEN 起点在 fen_codec 中实现，不在此耦合。
//
// 与国际象棋 / 国际跳棋的差异：
//   · 没有「吃子计数」「王步数」等派生字段 —— 象棋只有「轮次方」一个维度。
//   · 将帅照面（flying generals）是**局面合法性**而非着法规则，
//     因此在引擎里按"将军被攻击"处理，见 engine/move_generator.dart。

import '../constants/xiangqi_constants.dart';
import 'piece.dart';

/// 不可变棋盘状态。
class XiangqiBoardState {
  final List<int?> _cells;

  /// 当前轮次方
  final XiangqiColor sideToMove;

  const XiangqiBoardState._(this._cells, this.sideToMove);

  /// 起始局面（红先）。
  ///
  /// 直接 inline 起始排布，避免 board_state → fen_codec 循环依赖。
  factory XiangqiBoardState.initial() {
    final cells = List<int?>.filled(kXiangqiCells, null, growable: false);
    void place(int row, int col, XiangqiPiece p) {
      cells[xiangqiIndex(row, col)] = p.pack();
    }

    // row 0 —— 黑方底线：车马象士将士象马车
    const blackBack = [
      XiangqiPieceType.chariot,
      XiangqiPieceType.horse,
      XiangqiPieceType.elephant,
      XiangqiPieceType.advisor,
      XiangqiPieceType.general,
      XiangqiPieceType.advisor,
      XiangqiPieceType.elephant,
      XiangqiPieceType.horse,
      XiangqiPieceType.chariot,
    ];
    for (var col = 0; col < kXiangqiCols; col++) {
      place(0, col, XiangqiPiece(XiangqiColor.black, blackBack[col]));
    }

    // row 2 / row 7 —— 双炮（col 1 与 col 7）
    //
    // ⚠ 布局与 FEN 的对应关系（row 0 = 黑方底线，row 9 = 红方底线）：
    //   row 0 车马象士将士象马车 · row 1 空 · row 2 炮 · row 3 卒
    //   row 4 空 · row 5 空
    //   row 6 兵 · row 7 炮 · row 8 空 · row 9 车马相士帅仕相马车
    // 红炮在 row 7（不是 row 8）—— 整盘对 180° 旋转对称（红先 / 黑先
    // 走法数相同，初始局面双方各 44 步）。
    place(2, 1, XiangqiPiece.blackCannon);
    place(2, 7, XiangqiPiece.blackCannon);
    place(7, 1, XiangqiPiece.redCannon);
    place(7, 7, XiangqiPiece.redCannon);

    // row 3 / row 6 —— 五卒五兵（col 0,2,4,6,8）
    for (var col = 0; col < kXiangqiCols; col += 2) {
      place(3, col, XiangqiPiece.blackPawn);
      place(6, col, XiangqiPiece.redPawn);
    }

    // row 9 —— 红方底线：车马相士帅仕相马车
    const redBack = [
      XiangqiPieceType.chariot,
      XiangqiPieceType.horse,
      XiangqiPieceType.elephant,
      XiangqiPieceType.advisor,
      XiangqiPieceType.general,
      XiangqiPieceType.advisor,
      XiangqiPieceType.elephant,
      XiangqiPieceType.horse,
      XiangqiPieceType.chariot,
    ];
    for (var col = 0; col < kXiangqiCols; col++) {
      place(9, col, XiangqiPiece(XiangqiColor.red, redBack[col]));
    }

    return XiangqiBoardState._(cells, XiangqiColor.red);
  }

  /// 任意状态构造
  factory XiangqiBoardState({
    required List<int?> cells,
    required XiangqiColor sideToMove,
  }) {
    assert(cells.length == kXiangqiCells, 'board must be 90 cells');
    return XiangqiBoardState._(List<int?>.of(cells), sideToMove);
  }

  /// 公开只读视图：90 个 packed slot
  List<int?> get cells => _cells;

  /// 该格是否空
  bool isEmpty(int index) => _cells[index] == null;

  /// 该格是否有子
  bool isOccupied(int index) => _cells[index] != null;

  /// 该格棋子（null = 空）
  XiangqiPiece? pieceAt(int index) => _cells[index] == null
      ? null
      : XiangqiPiece.unpack(_cells[index]!);

  /// 该格颜色（null = 空）
  XiangqiColor? colorAt(int index) => pieceAt(index)?.color;

  /// 遍历所有非空格：(index, piece)
  Iterable<(int, XiangqiPiece)> get occupied sync* {
    for (var i = 0; i < _cells.length; i++) {
      final slot = _cells[i];
      if (slot == null) continue;
      yield (i, XiangqiPiece.unpack(slot));
    }
  }

  /// 某方所有子的格索引
  List<int> squaresOf(XiangqiColor color) {
    final out = <int>[];
    for (final (idx, piece) in occupied) {
      if (piece.color == color) out.add(idx);
    }
    return out;
  }

  /// 某方棋子数
  int countOf(XiangqiColor color) {
    var n = 0;
    for (final (_, piece) in occupied) {
      if (piece.color == color) n++;
    }
    return n;
  }

  /// 某方将/帅所在格（无则 -1 —— 正常对局中恒存在）
  int generalSquareOf(XiangqiColor color) {
    for (final (idx, piece) in occupied) {
      if (piece.color == color && piece.isGeneral) return idx;
    }
    return -1;
  }

  /// 不可变更新：返回新 XiangqiBoardState
  XiangqiBoardState copyWith({
    List<int?>? cells,
    XiangqiColor? sideToMove,
  }) {
    return XiangqiBoardState(
      cells: cells ?? _cells,
      sideToMove: sideToMove ?? this.sideToMove,
    );
  }

  /// 单一格子替换（不可变）
  XiangqiBoardState putCell(int index, int? packed) {
    final next = List<int?>.of(_cells);
    next[index] = packed;
    return copyWith(cells: next);
  }

  /// 深拷贝
  XiangqiBoardState copy() => XiangqiBoardState(
        cells: List<int?>.of(_cells),
        sideToMove: sideToMove,
      );

  /// 局面键（用于重复局面检测 / 快照差分）：棋盘 + 轮次方。
  ///
  /// 紧凑字符串编码 —— 90 格每格 4 bit（0 空 / 其余 packed 值）。
  /// 只需唯一性，不需可读性。
  String get positionKey {
    final buf = StringBuffer(sideToMove == XiangqiColor.red ? 'R' : 'B');
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
    if (other is! XiangqiBoardState) return false;
    if (sideToMove != other.sideToMove) return false;
    for (var i = 0; i < _cells.length; i++) {
      if (_cells[i] != other._cells[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    var h = Object.hash(sideToMove, kXiangqiCells);
    for (final c in _cells) {
      h = Object.hash(h, c);
    }
    return h;
  }
}
