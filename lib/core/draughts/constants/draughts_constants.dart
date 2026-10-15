// lib/core/draughts/constants/draughts_constants.dart
//
// 国际跳棋（International Draughts 10×10）常量
// 棋盘尺寸、可用格判定、方格编号(1-50) ↔ 内部坐标映射、初始布局。
//
// 几何约定（本项目内部唯一坐标系统）：
//   · 内部用 (row, col)，0-based，row 0 在顶部、row 9 在底部（FEN 视角，白方在下方）。
//   · 棋子只落在深色格：`(row + col) % 2 == 1`（左下角 (9,0) → 深色，符合 FMJD 要求）。
//   · 1D 索引 = row * kDraughtsCols + col，共 100 格（含 50 个不可用浅色格）。
//   · 对外方格号 1..50（PDN / FEN 用），从左上深色格起逐行蛇形。
//
// 参考 pydraughts 用 1..50 + 行列奇偶补偿做几何，极易出错；
// 本项目一律 (row,col) 直算，只在 FEN/PDN 边界换算编号。

/// 棋盘行数
const int kDraughtsRows = 10;

/// 棋盘列数
const int kDraughtsCols = 10;

/// 格子总数 = 100（含 50 个不可用浅色格）
const int kDraughtsCells = kDraughtsRows * kDraughtsCols;

/// 每方可落子的深色格数 = 50（= 棋盘方格号上限）
const int kDraughtsPlayableSquares = 50;

/// 每方起始棋子数
const int kDraughtsPiecesPerSide = 20;

/// 初始 FEN（白先，白占 31-50、黑占 1-20）
const String kDraughtsStartingFen = 'W:W31-50:B1-20';

/// 四个斜向 (dRow, dCol)
const List<(int, int)> kDraughtsDiagonals = [
  (-1, -1), (-1, 1), (1, -1), (1, 1),
];

/// 是否是棋盘内坐标
bool draughtsOnBoard(int row, int col) =>
    row >= 0 && row < kDraughtsRows && col >= 0 && col < kDraughtsCols;

/// 该坐标是否是可用深色格（含越界检查）
bool draughtsIsPlayable(int row, int col) =>
    draughtsOnBoard(row, col) && (row + col) % 2 == 1;

/// (row, col) → 1D 索引 (0..99)
int draughtsIndex(int row, int col) => row * kDraughtsCols + col;

/// 1D 索引 → row
int draughtsRowOf(int index) => index ~/ kDraughtsCols;

/// 1D 索引 → col
int draughtsColOf(int index) => index % kDraughtsCols;

/// (row, col) → 方格号 1..50（PDN/FEN 用）；非深色格返回 -1
int draughtsSquareNumber(int row, int col) {
  if (!draughtsIsPlayable(row, col)) return -1;
  return row * (kDraughtsCols ~/ 2) + (col ~/ 2) + 1;
}

/// 方格号 1..50 → 1D 索引；非法返回 -1
int draughtsIndexFromSquareNumber(int square) {
  if (square < 1 || square > kDraughtsPlayableSquares) return -1;
  final zero = square - 1;
  final row = zero ~/ (kDraughtsCols ~/ 2);
  final withinRow = zero % (kDraughtsCols ~/ 2);
  // 偶数行（0-based）深色格起于 col 1，奇数行起于 col 0
  final col = row.isEven ? withinRow * 2 + 1 : withinRow * 2;
  return draughtsIndex(row, col);
}

/// 1D 索引 → 方格号 1..50；非深色格返回 -1
int draughtsSquareNumberOfIndex(int index) =>
    draughtsSquareNumber(draughtsRowOf(index), draughtsColOf(index));

/// 该行是否属于某方的"底线"（升王行）
/// 白方（底部，row 递增向下）升王行 = row 0；黑方升王行 = row 9。
int draughtsPromotionRowFor(bool isWhite) => isWhite ? 0 : kDraughtsRows - 1;

/// 兵的"前进"方向：白方 row 递减、黑方 row 递增
int draughtsForwardDeltaFor(bool isWhite) => isWhite ? -1 : 1;

/// 初始局面：白占 31-50（底部 4 行）、黑占 1-20（顶部 4 行）。
///
/// 返回 100 长度、值为 1..50 方格号（空格为 0）的布局表，
/// 由调用方（board_state）转成 packed slot，避免此处耦合棋子编码。
List<int> draughtsInitialLayout() {
  final layout = List<int>.filled(kDraughtsCells, 0, growable: false);
  for (var row = 0; row < kDraughtsRows; row++) {
    for (var col = 0; col < kDraughtsCols; col++) {
      if (!draughtsIsPlayable(row, col)) continue;
      final n = draughtsSquareNumber(row, col);
      layout[draughtsIndex(row, col)] = n;
    }
  }
  return layout;
}

/// 各方起始方格号区间（含端点）。
/// 白 = 31..50，黑 = 1..20 —— 与 [kDraughtsStartingFen] 一致。
bool draughtsIsWhiteStartSquare(int square) => square >= 31 && square <= 50;
bool draughtsIsBlackStartSquare(int square) => square >= 1 && square <= 20;
