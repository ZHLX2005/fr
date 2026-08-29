// lib/core/chess/models/board_state.dart
//
// 8x8 棋盘不可变状态（immutable value）
// 设计：
//   · 内部用 Uint8List (可选，简化用 List<int?>）长度 64
//     — 避免 64 个对象（小棋盘 + GC 友好）
//     — packing schema: 见 PieceSlot.pack / unpack
//   · 任何"下一步"通过 copyWith 返回新实例，永不 mutate
//   · FEN 起点在 fen_codec 中实现，不在此耦合
//
// PieceSlot packing:
//   bits 0..3  = PieceType 索引 (0..5)
//   bits 4     = PieceColor (0 = white, 1 = black)
//   bits 5..7  = 保留

import '../constants/chess_constants.dart';
import 'piece.dart';

/// 内部 packed int 表示一个棋格（含棋子或空）
class PieceSlot {
  /// pack helper：type 必须 0..5，color 必须 0/1
  /// 返回 null = 空格子
  static int? pack(PieceType? type, PieceColor? color, {int flags = 0}) {
    if (type == null && color == null) return null;
    final t = type!.index; // 0..5
    final c = color == PieceColor.black ? 1 : 0;
    return flags | (c << 4) | t;
  }

  /// 0 = white，1 = black
  static int unpackColor(int slot) => (slot >> 4) & 1;

  /// 0..5
  static int unpackTypeIndex(int slot) => slot & 0x0F;

  static int unpackFlags(int slot) => (slot >> 5) & 0x07;

  static PieceType unpackType(int slot) =>
      PieceType.values[unpackTypeIndex(slot)];

  static PieceColor unpackColorEnum(int slot) =>
      unpackColor(slot) == 0 ? PieceColor.white : PieceColor.black;
}

/// 不可变棋盘状态
///
/// 一个棋盘 = 64 packed slot + 一组状态字段（轮次/易位权/吃过路兵目标格/
/// 半回合计数 / 全回合数）。
class BoardState {
  /// 64 个 packed slots（空位为 0；0 是空格的 sentinel —— 用 `board[i] != null` 不行，
  /// 我们用 Uint8List，0 兼任空 + null sentinel；type 0 也是 king，
  /// 但通过"未 pack" + `slot & 0x0F == 0` 也识别为 king，要靠外部 keep _isEmpty 标记。
  ///
  /// 为消除歧义：board 实际存 `List<int?>`（可空 64 元素）。
  final List<int?> _board;

  /// 当前轮次方（白/黑）
  final PieceColor sideToMove;

  /// 王车易位权（FEN: KQkq 字段）
  final CastlingRights castling;

  /// 吃过路兵目标格（1D index 或 null）
  /// FEN en-passant field
  final int? enPassantTarget;

  /// 半回合计数（FEN: halfmove clock）—— 自上次吃子/兵进以来的半回合数
  final int halfmoveClock;

  /// 全回合数（FEN: fullmove number）—— 当前轮到 black 时递增
  final int fullmoveNumber;

  const BoardState._(
    this._board,
    this.sideToMove,
    this.castling,
    this.enPassantTarget,
    this.halfmoveClock,
    this.fullmoveNumber,
  );

  /// 起始局面（白方先走）
  ///
  /// 直接 inline 起始排布，避免 board_state → fen_codec 循环依赖。
  /// FEN string `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`
  factory BoardState.initial() {
    final b = List<int?>.filled(64, null, growable: false);
    const whiteBackRank = 'RNBQKBNR';
    const whitePawnRow = 'PPPPPPPP';
    const blackPawnRow = 'pppppppp';
    const blackBackRank = 'rnbqkbnr';

    for (var c = 0; c < 8; c++) {
      b[0 * 8 + c] = PieceSlot.pack(pieceTypeFromFenChar(blackBackRank[c])!,
          PieceColor.black);
      b[1 * 8 + c] = PieceSlot.pack(pieceTypeFromFenChar(blackPawnRow[c])!,
          PieceColor.black);
      b[6 * 8 + c] = PieceSlot.pack(pieceTypeFromFenChar(whitePawnRow[c])!,
          PieceColor.white);
      b[7 * 8 + c] = PieceSlot.pack(pieceTypeFromFenChar(whiteBackRank[c])!,
          PieceColor.white);
    }
    return BoardState(
      board: b,
      sideToMove: PieceColor.white,
      castling: const CastlingRights.all(),
    );
  }

  /// 任意 BoardState
  factory BoardState({
    required List<int?> board,
    required PieceColor sideToMove,
    CastlingRights castling = const CastlingRights.none(),
    int? enPassantTarget,
    int halfmoveClock = 0,
    int fullmoveNumber = 1,
  }) {
    assert(board.length == kBoardSquares, 'board must be 64 slots');
    return BoardState._(
      List<int?>.of(board),
      sideToMove,
      castling,
      enPassantTarget,
      halfmoveClock,
      fullmoveNumber,
    );
  }

  /// 索引语法糖：square 为 1D index (0..63)
  int? slotAt(int square) => _board[square];
  PieceType? pieceTypeAt(int square) {
    final slot = _board[square];
    if (slot == null) return null;
    return PieceSlot.unpackType(slot);
  }

  PieceColor? pieceColorAt(int square) {
    final slot = _board[square];
    if (slot == null) return null;
    return PieceSlot.unpackColorEnum(slot);
  }

  /// 该格是不是空
  bool isEmpty(int square) => _board[square] == null;

  bool isOccupied(int square) => _board[square] != null;

  /// 公开视图：64 个 packed slot（同 package 内访问）
  ///
  /// 用于 FEN 编解码、内部检测、UI 序列化。
  /// Dart private（_前缘）是 library-scoped（单文件）；我们提供公开 `cells` getter 让
  /// 同一 package 下其他 .dart 文件也能拿到 64 slots。
  List<int?> get cells => _board;

  /// 内部构造（package 可见）。新 Dart 推荐：`part` + 同库 / 或公开 getter。

  /// 查找指定颜色王的 1D 格子索引
  /// 用于将军判定。棋盘永远只有一个白王 / 一个黑王。
  int? findKing(PieceColor color) {
    for (var i = 0; i < _board.length; i++) {
      final slot = _board[i];
      if (slot == null) continue;
      if (PieceSlot.unpackType(slot) == PieceType.king &&
          PieceSlot.unpackColorEnum(slot) == color) {
        return i;
      }
    }
    return null;
  }

  /// 不可变更新：返回新 BoardState
  BoardState copyWith({
    List<int?>? board,
    PieceColor? sideToMove,
    CastlingRights? castling,
    int? enPassantTarget,
    bool clearEnPassant = false,
    int? halfmoveClock,
    int? fullmoveNumber,
  }) {
    return BoardState(
      board: board ?? _board,
      sideToMove: sideToMove ?? this.sideToMove,
      castling: castling ?? this.castling,
      enPassantTarget: clearEnPassant ? null : (enPassantTarget ?? this.enPassantTarget),
      halfmoveClock: halfmoveClock ?? this.halfmoveClock,
      fullmoveNumber: fullmoveNumber ?? this.fullmoveNumber,
    );
  }

  /// 单一格子替换：返回新 BoardState（不可变）
  ///
  /// slot=null 表示空格
  BoardState putSlot(int square, int? slot) {
    final next = List<int?>.of(_board);
    next[square] = slot;
    return copyWith(board: next);
  }

  /// 是否处于"已被将军"状态（sideToMove 方的王在被攻击）
  /// 不检测已将军的方向，仅给出布尔。
  ///
  /// 算法约定：调用方传入"攻击方"颜色（即 opposite(sideToMove)）
  ///   && 与 makeMove 后用于撤销判定
  bool isInCheck(PieceColor colorOfKing, List<int> attackedSquares) {
    final king = findKing(colorOfKing);
    if (king == null) return false;
    return attackedSquares.contains(king);
  }

  /// 深拷贝（同 Dart 引用语义，返回完全独立的新对象）
  BoardState copy() {
    return BoardState(
      board: List<int?>.of(_board),
      sideToMove: sideToMove,
      castling: castling,
      enPassantTarget: enPassantTarget,
      halfmoveClock: halfmoveClock,
      fullmoveNumber: fullmoveNumber,
    );
  }

  // ───────────── hashCode / operator == ─────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BoardState) return false;
    if (sideToMove != other.sideToMove) return false;
    if (castling != other.castling) return false;
    if (enPassantTarget != other.enPassantTarget) return false;
    if (halfmoveClock != other.halfmoveClock) return false;
    if (fullmoveNumber != other.fullmoveNumber) return false;
    for (var i = 0; i < _board.length; i++) {
      if (_board[i] != other._board[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    final parts = <int>[
      sideToMove.index,
      castling._bits,
      enPassantTarget ?? -1,
      halfmoveClock,
      fullmoveNumber,
      ..._board.whereType<int>(), // 实际非空 slots
    ];
    return Object.hashAll(parts);
  }
}

/// 王车易位权 —— 4 个 bool 打包成 int（一字节 8 位，可用 4 位即可）
class CastlingRights {
  final bool whiteKingSide;
  final bool whiteQueenSide;
  final bool blackKingSide;
  final bool blackQueenSide;

  const CastlingRights({
    required this.whiteKingSide,
    required this.whiteQueenSide,
    required this.blackKingSide,
    required this.blackQueenSide,
  });

  const CastlingRights.none()
      : whiteKingSide = false,
        whiteQueenSide = false,
        blackKingSide = false,
        blackQueenSide = false;

  const CastlingRights.all()
      : whiteKingSide = true,
        whiteQueenSide = true,
        blackKingSide = true,
        blackQueenSide = true;

  static CastlingRights fromFenString(String s) {
    if (s == '-') return const CastlingRights.none();
    return CastlingRights(
      whiteKingSide: s.contains('K'),
      whiteQueenSide: s.contains('Q'),
      blackKingSide: s.contains('k'),
      blackQueenSide: s.contains('q'),
    );
  }

  String toFenString() {
    if (!whiteKingSide &&
        !whiteQueenSide &&
        !blackKingSide &&
        !blackQueenSide) {
      return '-';
    }
    final buf = StringBuffer();
    if (whiteKingSide) buf.write('K');
    if (whiteQueenSide) buf.write('Q');
    if (blackKingSide) buf.write('k');
    if (blackQueenSide) buf.write('q');
    return buf.toString();
  }

  int get _bits =>
      (whiteKingSide ? 1 : 0) |
      (whiteQueenSide ? 2 : 0) |
      (blackKingSide ? 4 : 0) |
      (blackQueenSide ? 8 : 0);

  @override
  bool operator ==(Object other) =>
      other is CastlingRights &&
      whiteKingSide == other.whiteKingSide &&
      whiteQueenSide == other.whiteQueenSide &&
      blackKingSide == other.blackKingSide &&
      blackQueenSide == other.blackQueenSide;

  @override
  int get hashCode => Object.hash(
        whiteKingSide,
        whiteQueenSide,
        blackKingSide,
        blackQueenSide,
      );
}

// dart:ui 包不在 chess 模块依赖中（业务模块不依赖 Flutter），用 const 标记泛型
// 这里我们用 meta 替代，确保 @immutable 在没有 dart:ui 导入时也能编译。
// 改为：CastlingRights 自身已在常量构造 + 所有字段 final，达到同等 immutable 效果。

// ⚠️ dart:ui 不在 chess 模块依赖中 —— @immutable 已被移除以避免导入
// ⚠️ 下划线开头是 Dart library-private，只有 board_state.dart 内部可访问 _board
