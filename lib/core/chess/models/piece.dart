// lib/core/chess/models/piece.dart
//
// 棋子类型 + 颜色
// 注意：本文件不含 unicode / 资产路径 → 那是 UI 端关注点。
// 引擎/算法只认 PieceType + PieceColor 两个枚举。

/// 棋子 6 种类型
///
/// 枚举顺序对应 FEN 字符索引（不严格，FEN 字符索引走专门函数）
enum PieceType { king, queen, rook, bishop, knight, pawn }

/// 棋子颜色
///
/// 白方先走。FEN / PGN 标准 = `w`（白）/ `b`（黑）。
enum PieceColor { white, black }

/// PieceColor 反色
PieceColor opposite(PieceColor c) =>
    c == PieceColor.white ? PieceColor.black : PieceColor.white;

/// PieceColor → FEN 字符
String pieceColorToFenChar(PieceColor c) =>
    c == PieceColor.white ? 'w' : 'b';

/// FEN 字符 → PieceColor
PieceColor pieceColorFromFenChar(String ch) =>
    ch == 'w' ? PieceColor.white : PieceColor.black;

/// FEN 棋子字符 → PieceType
///
/// 接受大小写；返回 null 当非法
/// K=k 王, Q=q 后, R=r 车, B=b 象, N=n 马, P=p 兵
PieceType? pieceTypeFromFenChar(String ch) {
  switch (ch.toLowerCase()) {
    case 'k':
      return PieceType.king;
    case 'q':
      return PieceType.queen;
    case 'r':
      return PieceType.rook;
    case 'b':
      return PieceType.bishop;
    case 'n':
      return PieceType.knight;
    case 'p':
      return PieceType.pawn;
    default:
      return null;
  }
}

/// FEN 棋子字符 → (PieceType, PieceColor)
/// 大写 = 白方，小写 = 黑方
(PieceType, PieceColor)? pieceFromFenChar(String ch) {
  final t = pieceTypeFromFenChar(ch);
  if (t == null) return null;
  final c = ch == ch.toUpperCase()
      ? PieceColor.white
      : PieceColor.black;
  return (t, c);
}

/// PieceType + PieceColor → FEN 字符
String pieceToFenChar(PieceType t, PieceColor c) {
  final base = switch (t) {
    PieceType.king => 'k',
    PieceType.queen => 'q',
    PieceType.rook => 'r',
    PieceType.bishop => 'b',
    PieceType.knight => 'n',
    PieceType.pawn => 'p',
  };
  return c == PieceColor.white ? base.toUpperCase() : base;
}
