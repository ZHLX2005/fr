// lib/core/chess/constants/chess_constants.dart
//
// 国际象棋（Chess）常量
// 棋盘尺寸、FEN 起点、坐标辅助、unicode 棋子符号。
//
// 设计：所有"业务几何"集中在此，其他文件只能 const 引用，禁止散落。
// 颜色 / 主题色走 ColorStrategy，棋盘尺寸/格子编号走这里。

/// 棋盘行数（rank 1-8，白方在下方 1/2 行）
const int kBoardRows = 8;

/// 棋盘列数（file a-h）
const int kBoardCols = 8;

/// 棋盘格子总数 = kBoardRows * kBoardCols
const int kBoardSquares = kBoardRows * kBoardCols;

/// row 0 在白方视角是第 8 排（黑方底线），row 7 在白方视角是第 1 排（白方底线）
/// 这是 FEN 视角约定：白方从底部向上看。

/// FEN 标准起点（白方在下，黑方在上）
/// 1D index = row * kBoardCols + col
const String kStartingFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// FEN 字符串的空位置标记
const String kFenEmpty = '8';

/// Unicode 棋子符号（用以 unicode fallback 演示，非业务唯一 ID）
const Map<String, String> kUnicodePieces = {
  // 白方用实心字符，黑方用空心字符
  'K': '♔', // 白王
  'Q': '♕', // 白后
  'R': '♖', // 白车
  'B': '♗', // 白象
  'N': '♘', // 白马
  'P': '♙', // 白兵
  'k': '♚', // 黑王
  'q': '♛', // 黑后
  'r': '♜', // 黑车
  'b': '♝', // 黑象
  'n': '♞', // 黑马
  'p': '♟', // 黑兵
};

/// 皮肤 piece key（'wK' / 'bp' …）→ unicode 字符兜底。
///
/// 统一供三处使用（chess_board 缺图回退、ChessPiece.errorBuilder、
/// 升变面板缺图回退）：key 首字符 w/b 决定 FEN 大小写，再查
/// [kUnicodePieces]；未知 key 返回 '?'。
String chessPieceUnicodeFallback(String skinKey) {
  final isWhite = skinKey.startsWith('w');
  final typeChar = skinKey.substring(1).toLowerCase();
  final fenChar = isWhite ? typeChar.toUpperCase() : typeChar;
  return kUnicodePieces[fenChar] ?? '?';
}

/// 字母 → 文件（column）
const String kFiles = 'abcdefgh';

/// 行 → 数字（rank）
/// FEN 中行用数字表示，白方底线是 1
/// row 0 ↔ rank 8，row 7 ↔ rank 1
int rankFromRow(int row) => kBoardRows - row;

/// row ↔ rank 反向
int rowFromRank(int rank) => kBoardRows - rank;

/// file 字母 ↔ col
/// file 'a' ↔ col 0，file 'h' ↔ col 7
int colFromFile(String f) => kFiles.indexOf(f);

/// col → file 字母
String fileFromCol(int col) => kFiles[col];

/// 标准代数记号（SAN/algebraic）→ 1D index
/// 接受 "a1".."h8"（永远白方视角）
/// 错误时返回 -1
int squareToIndex(String sq) {
  if (sq.length != 2) return -1;
  final file = sq[0].toLowerCase();
  final rank = sq[1];
  final col = colFromFile(file);
  final r = int.tryParse(rank);
  if (col < 0 || r == null || r < 1 || r > 8) return -1;
  return rowFromRank(r) * kBoardCols + col;
}

/// 1D index → algebraic（永远白方视角）
String indexToSquare(int index) {
  final row = index ~/ kBoardCols;
  final col = index % kBoardCols;
  return fileFromCol(col) + rankFromRow(row).toString();
}

/// 走法 FEN/PGN 用：起始格 → 目标格 + 升变字
/// 返回对象请用 models/move.dart 的 Move 类（不做几何转换）
String shortAlgebraic(int fromIndex, int toIndex) {
  return indexToSquare(fromIndex) + indexToSquare(toIndex);
}
