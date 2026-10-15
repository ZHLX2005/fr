// lib/core/draughts/models/piece.dart
//
// 棋子颜色 + 兵/王区分。
// 与国际象棋不同：跳棋只有两个"兵种"（兵 man / 王 king），
// 王不是独立棋子而是兵的晋升状态 → 用 DraughtsPiece 一个值类型表达。
//
// 本文件不含 unicode / 资产路径（那是 UI 关注点）。

/// 棋子颜色。白方先走（FMJD 规则）。
enum DraughtsColor { white, black }

/// DraughtsColor 反色
DraughtsColor draughtsOpposite(DraughtsColor c) =>
    c == DraughtsColor.white ? DraughtsColor.black : DraughtsColor.white;

/// 不可变棋子：颜色 + 是否王。
///
/// 不持有位置 —— 位置是棋盘状态的属性，不是棋子的属性
/// （与国际象棋 PieceSlot 的 packed 方案等价，但这里只需 2 bit）。
class DraughtsPiece {
  /// 颜色
  final DraughtsColor color;

  /// 是否已升王（flying king）
  final bool isKing;

  const DraughtsPiece(this.color, {this.isKing = false});

  /// 便利：白兵
  static const DraughtsPiece whiteMan =
      DraughtsPiece(DraughtsColor.white);
  static const DraughtsPiece blackMan =
      DraughtsPiece(DraughtsColor.black);

  bool get isWhite => color == DraughtsColor.white;
  bool get isMan => !isKing;

  /// 晋升为王（返回新实例）
  DraughtsPiece promote() => DraughtsPiece(color, isKing: true);

  /// 兵的"前进"方向：白方 row 递减（-1）、黑方 row 递增（+1）
  int get forwardDelta => isWhite ? -1 : 1;

  /// pack 成 1 个 int（board 内部存 `int?`；null = 空格）
  /// bits 0 = color (0 white / 1 black)，bit 1 = isKing
  int pack() => (isKing ? 2 : 0) | (isWhite ? 0 : 1);

  /// unpack
  static DraughtsPiece unpack(int packed) => DraughtsPiece(
        (packed & 1) == 0 ? DraughtsColor.white : DraughtsColor.black,
        isKing: (packed & 2) != 0,
      );

  /// FEN 字符：白兵 W / 白王 K'? —— FMJD 用大写 = 白、小写 = 黑，
  /// 本文档统一 w/W（白兵/白王）、b/B（黑兵/黑王），由 pdn_codec 决定大小写语义。
  String get fenChar {
    final base = isKing ? 'K' : 'M';
    return isWhite ? base : base.toLowerCase();
  }

  @override
  bool operator ==(Object other) =>
      other is DraughtsPiece && other.color == color && other.isKing == isKing;

  @override
  int get hashCode => Object.hash(color, isKing);

  @override
  String toString() => '${isWhite ? 'w' : 'b'}${isKing ? 'K' : 'M'}';
}

/// 单个格子：null = 空，否则是棋子
typedef DraughtsSlot = int?;
