// lib/core/xiangqi/constants/xiangqi_constants.dart
//
// 中国象棋（Xiangqi / Chinese Chess 9×10）常量
// 棋盘尺寸、九宫、楚河汉界、棋子编码、初始布局、走法记号。
//
// 几何约定（本项目内部唯一坐标系统）：
//   · 内部用 (row, col)，0-based，row 0 在顶部（黑方底线）、row 9 在底部（红方底线）。
//   · 1D 索引 = row * kXiangqiCols + col，共 90 格。
//   · 红方（红帅）先走 —— 中国象棋「红先黑后」，与国际象棋（白先）、
//     国际跳棋（白先）相反，这里用「红 = red = 先手方」表达。
//   · 九宫（palace）：col ∈ [3,5]，row ∈ [0,2] 为黑将九宫、row ∈ [7,9] 为红帅九宫。
//   · 楚河汉界（river）：row 4 与 row 5 之间 —— 黑方（row ≤ 4）在河内，
//     红方（row ≥ 5）在河内；象（相）不过河，卒（兵）过河后可横走。
//
// 与国际象棋 / 国际跳棋的差异（保持风格平行、实现独立）：
//   · 无升变（棋种固定 7 种，没有 pawn→queen 之类的晋升）。
//   · 无吃过路兵、无易位、无王车易位。
//   · 有「蹩马腿」（马走日被相邻正交子挡）、「塞象眼」（象走田被中点挡）、
//     「炮架」（炮吃子必须隔且仅隔一子）、「将帅照面」（双将同列中间无子非法）。
//   · 困毙（stale 但无着可走）判负 —— 象棋里不是和棋。

/// 棋盘行数（横线数，10 条）
const int kXiangqiRows = 10;

/// 棋盘列数（纵线数，9 条）
const int kXiangqiCols = 9;

/// 格子总数 = 90
const int kXiangqiCells = kXiangqiRows * kXiangqiCols;

/// 九宫列区间（闭区间）：col ∈ [3, 5]
const int kXiangqiPalaceMinCol = 3;
const int kXiangqiPalaceMaxCol = 5;

/// 黑方九宫行区间（闭区间）：row ∈ [0, 2]
const int kXiangqiBlackPalaceMinRow = 0;
const int kXiangqiBlackPalaceMaxRow = 2;

/// 红方九宫行区间（闭区间）：row ∈ [7, 9]
const int kXiangqiRedPalaceMinRow = 7;
const int kXiangqiRedPalaceMaxRow = 9;

/// 楚河汉界分界：row ≤ 4 属黑方半场，row ≥ 5 属红方半场
const int kXiangqiRiverRow = 4;

/// 红方（红帅）初始 FEN —— 中国象棋标准布局，红先。
///
/// 布局（自上而下 = row 0 → row 9）：
///   row 0: r n b a k a b n r   （车马象士将士象马车）
///   row 1: · · · · · · · · ·
///   row 2: · · c · · · c · ·   （双炮）
///   row 3: p · p · p · p · p   （五卒）
///   row 4: · · · · · · · · ·
///   row 5: · · · · · · · · ·
///   row 6: P · P · P · P · P   （五兵）
///   row 7: · · · · · · · · ·
///   row 8: · · C · · · C · ·   （双炮）
///   row 9: R N B A K A B N R   （车马相士帅仕相马车）
const String kXiangqiStartingFen =
    'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1';

/// 初始棋谱 FEN（无走子时的起点，与 [kXiangqiStartingFen] 一致）
const String kXiangqiStartingPosition = 'rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/'
    'P1P1P1P1P/1C5C1/9/RNBAKABNR';

/// 棋盘宽高比（9 列间距 × 10 行间距）—— 供 AspectRatio 直接消费。
const double kXiangqiBoardAspectRatio = kXiangqiCols / kXiangqiRows;

/// 是否是棋盘内坐标
bool xiangqiOnBoard(int row, int col) =>
    row >= 0 && row < kXiangqiRows && col >= 0 && col < kXiangqiCols;

/// (row, col) → 1D 索引 (0..89)
int xiangqiIndex(int row, int col) => row * kXiangqiCols + col;

/// 1D 索引 → row
int xiangqiRowOf(int index) => index ~/ kXiangqiCols;

/// 1D 索引 → col
int xiangqiColOf(int index) => index % kXiangqiCols;

/// 该格是否属于某方的九宫
bool xiangqiInPalaceOf(int row, int col, {required bool isRed}) {
  if (col < kXiangqiPalaceMinCol || col > kXiangqiPalaceMaxCol) return false;
  return isRed
      ? row >= kXiangqiRedPalaceMinRow && row <= kXiangqiRedPalaceMaxRow
      : row >= kXiangqiBlackPalaceMinRow && row <= kXiangqiBlackPalaceMaxRow;
}

/// 该格所属半场：0 = 黑方半场（row 0..4），1 = 红方半场（row 5..9）。
///
/// 楚河汉界把棋盘切成两半 —— **象（相）不能跨河**，判定依据是
/// 「起点与终点是否同属一个半场」，与棋子颜色无关：一只已经过河的
/// 红象仍然不能回到黑方半场，只能在红方半场内活动。
int xiangqiHalfOf(int row) => row <= kXiangqiRiverRow ? 0 : 1;

/// 该格是否已过河（兵/卒过河后可横走）。
///
/// 红方过河 = row ≤ [kXiangqiRiverRow]；黑方过河 = row > [kXiangqiRiverRow]。
bool xiangqiCrossedRiver(int row, {required bool isRed}) =>
    isRed ? row <= kXiangqiRiverRow : row > kXiangqiRiverRow;

/// 1D 索引 → 记号名（如 "e0"）：列用 a..i，行用 0..9。
///
/// 记号只用于协议层与日志（走法串 / 调试），不参与规则判定。
String xiangqiSquareName(int index) {
  final col = xiangqiColOf(index);
  final row = xiangqiRowOf(index);
  return '${String.fromCharCode(97 + col)}$row';
}

/// 记号名 → 1D 索引；非法返回 -1
int xiangqiIndexFromName(String name) {
  if (name.length != 2) return -1;
  final colCode = name.codeUnitAt(0);
  if (colCode < 97 || colCode > 97 + kXiangqiCols - 1) return -1;
  final rowCode = name.codeUnitAt(1);
  if (rowCode < 48 || rowCode > 48 + kXiangqiRows - 1) return -1;
  return xiangqiIndex(rowCode - 48, colCode - 97);
}
