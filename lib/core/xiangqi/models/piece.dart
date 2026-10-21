// lib/core/xiangqi/models/piece.dart
//
// 棋子颜色 + 棋种。7 种棋（中国象棋「七子」）：将/帅、士、象/相、马、车、炮、卒/兵。
//
// 与国际象棋 / 国际跳棋的差异：
//   · 颜色用「红 / 黑」（中国象棋传统），不用白 / 黑。
//   · 无升变 —— 棋种终身不变，所以不需要 draughts 那种 isKing 标志位。
//   · 将（帅）与帅（将）是同一棋种的两种字面，按颜色区分显示字。
//
// 本文件不含 unicode / 资产路径（那是 UI 关注点，SVG 渲染在 widgets/）。

/// 棋子颜色。红方先走（中国象棋「红先黑后」）。
enum XiangqiColor { red, black }

/// XiangqiColor 反色
XiangqiColor xiangqiOpposite(XiangqiColor c) =>
    c == XiangqiColor.red ? XiangqiColor.black : XiangqiColor.red;

/// 棋种（七子）
enum XiangqiPieceType {
  /// 将（黑）/ 帅（红）—— 九宫内活动，不可被将死
  general,

  /// 士 —— 九宫内斜走一格
  advisor,

  /// 象（黑）/ 相（红）—— 走田（斜二格），不过河，塞象眼
  elephant,

  /// 马 —— 走日（斜一横二），蹩马腿
  horse,

  /// 车 —— 直线滑行
  chariot,

  /// 炮 —— 不吃子同车；吃子须隔且仅隔一子（炮架）
  cannon,

  /// 卒（黑）/ 兵（红）—— 只进不退，过河后可横走
  pawn,
}

/// XiangqiPieceType 反色无关 —— 棋种与颜色正交，单独的反色辅助放颜色上。
///
/// 不可变棋子：颜色 + 棋种。
///
/// 不持有位置 —— 位置是棋盘状态的属性，不是棋子的属性
/// （与 draughts / chess 的 packed 方案等价）。
class XiangqiPiece {
  /// 颜色
  final XiangqiColor color;

  /// 棋种
  final XiangqiPieceType type;

  const XiangqiPiece(this.color, this.type);

  /// 便利：红方各棋种
  static const XiangqiPiece redGeneral =
      XiangqiPiece(XiangqiColor.red, XiangqiPieceType.general);
  static const XiangqiPiece redAdvisor =
      XiangqiPiece(XiangqiColor.red, XiangqiPieceType.advisor);
  static const XiangqiPiece redElephant =
      XiangqiPiece(XiangqiColor.red, XiangqiPieceType.elephant);
  static const XiangqiPiece redHorse =
      XiangqiPiece(XiangqiColor.red, XiangqiPieceType.horse);
  static const XiangqiPiece redChariot =
      XiangqiPiece(XiangqiColor.red, XiangqiPieceType.chariot);
  static const XiangqiPiece redCannon =
      XiangqiPiece(XiangqiColor.red, XiangqiPieceType.cannon);
  static const XiangqiPiece redPawn =
      XiangqiPiece(XiangqiColor.red, XiangqiPieceType.pawn);

  /// 便利：黑方各棋种
  static const XiangqiPiece blackGeneral =
      XiangqiPiece(XiangqiColor.black, XiangqiPieceType.general);
  static const XiangqiPiece blackAdvisor =
      XiangqiPiece(XiangqiColor.black, XiangqiPieceType.advisor);
  static const XiangqiPiece blackElephant =
      XiangqiPiece(XiangqiColor.black, XiangqiPieceType.elephant);
  static const XiangqiPiece blackHorse =
      XiangqiPiece(XiangqiColor.black, XiangqiPieceType.horse);
  static const XiangqiPiece blackChariot =
      XiangqiPiece(XiangqiColor.black, XiangqiPieceType.chariot);
  static const XiangqiPiece blackCannon =
      XiangqiPiece(XiangqiColor.black, XiangqiPieceType.cannon);
  static const XiangqiPiece blackPawn =
      XiangqiPiece(XiangqiColor.black, XiangqiPieceType.pawn);

  bool get isRed => color == XiangqiColor.red;

  bool get isBlack => color == XiangqiColor.black;

  /// 是否为将/帅（唯一的被将目标）
  bool get isGeneral => type == XiangqiPieceType.general;

  /// 该棋子的「前进方向」行增量：红方 -1（向上）、黑方 +1（向下）
  int get forwardDelta => isRed ? -1 : 1;

  /// pack 成 1 个 int（board 内部存 `int?`；null = 空格）
  /// bits 0..2 = 棋种（0..6），bit 3 = 颜色（0 红 / 1 黑）
  int pack() => type.index | (isBlack ? 8 : 0);

  /// unpack
  static XiangqiPiece unpack(int packed) => XiangqiPiece(
        (packed & 8) != 0 ? XiangqiColor.black : XiangqiColor.red,
        XiangqiPieceType.values[packed & 7],
      );

  /// FEN 字符：大写 = 红、小写 = 黑。
  ///
  /// 采用中国象棋通用记法（ICPC / WXF 风格）：
  ///   K 将/帅 · A 士 · B 象/相 · N 马 · R 车 · C 炮 · P 卒/兵
  String get fenChar {
    const upper = ['K', 'A', 'B', 'N', 'R', 'C', 'P'];
    final c = upper[type.index];
    return isRed ? c : c.toLowerCase();
  }

  /// 中文棋名（用于 UI 文案 / 引擎调试）。
  ///
  /// 红黑用不同汉字（帅/将、仕/士、相/象、兵/卒），
  /// 与棋盘实物一致 —— 中国象棋界面的传统写法。
  String get chineseName {
    if (isRed) {
      switch (type) {
        case XiangqiPieceType.general:
          return '帅';
        case XiangqiPieceType.advisor:
          return '仕';
        case XiangqiPieceType.elephant:
          return '相';
        case XiangqiPieceType.horse:
          return '马';
        case XiangqiPieceType.chariot:
          return '车';
        case XiangqiPieceType.cannon:
          return '炮';
        case XiangqiPieceType.pawn:
          return '兵';
      }
    }
    switch (type) {
      case XiangqiPieceType.general:
        return '将';
      case XiangqiPieceType.advisor:
        return '士';
      case XiangqiPieceType.elephant:
        return '象';
      case XiangqiPieceType.horse:
        return '马';
      case XiangqiPieceType.chariot:
        return '车';
      case XiangqiPieceType.cannon:
        return '炮';
      case XiangqiPieceType.pawn:
        return '卒';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is XiangqiPiece && other.color == color && other.type == type;

  @override
  int get hashCode => Object.hash(color, type);

  @override
  String toString() => '${isRed ? 'r' : 'b'}${type.name}';
}

/// 单个格子：null = 空，否则是棋子 packed 值
typedef XiangqiSlot = int?;
