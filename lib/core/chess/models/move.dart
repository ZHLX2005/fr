// lib/core/chess/models/move.dart
//
// 走法（不可变 value）：from / to / 升变 / 特殊标记（王车易位/吃过路兵/吃子）

import 'piece.dart';
import '../constants/chess_constants.dart'
    show indexToSquare, squareToIndex;

/// 特殊走法标记
enum MoveFlags {
  /// 普通走法（含吃子）
  none,

  /// 王车易位（王移动两格，对应车移动）
  castling,

  /// 吃过路兵
  enPassant,
}

/// 不可变走法
///
/// from / to 都是 1D 索引（0..63）
/// promotion 仅在兵到底线时有效
class Move {
  final int from;
  final int to;

  /// 若走法是兵升变，落子的棋子类型（不能是 king 或 pawn）
  /// 普通走法（含吃子）时为 null
  final PieceType? promotion;

  /// 走法的特殊属性
  final MoveFlags flag;

  /// 被吃掉的棋子位置（普通吃子是 to 位置；
  /// 吃过路兵是过路兵格的 position）
  final int? capturedSquare;

  /// 走法执行后是否造成对方被将军 / 将杀
  /// 此信息由 check_detector 在生成合法走法时一并计算
  final bool givesCheck;

  /// 走法执行后是否造成将杀
  final bool isCheckmate;

  const Move({
    required this.from,
    required this.to,
    this.promotion,
    this.flag = MoveFlags.none,
    this.capturedSquare,
    this.givesCheck = false,
    this.isCheckmate = false,
  });

  /// UCI 格式（"e2e4", "e7e8q"）：走法表示的简化形式，永远白方视角
  String toUci({PieceColor promotingColor = PieceColor.white}) {
    final fromSq = indexToSquare(from);
    final toSq = indexToSquare(to);
    if (promotion == null) return '$fromSq$toSq';
    final p = pieceToFenChar(promotion!, promotingColor);
    return '$fromSq$toSq$p';
  }

  /// 反向 UCI 解析
  factory Move.fromUci(String uci, {PieceColor sideToMove = PieceColor.white}) {
    if (uci.length < 4) {
      throw ArgumentError('Invalid UCI move: $uci');
    }
    final from = squareToIndex(uci.substring(0, 2));
    final to = squareToIndex(uci.substring(2, 4));
    final promo = uci.length >= 5
        ? pieceTypeFromFenChar(uci.substring(4, 5))
        : null;
    return Move(
      from: from,
      to: to,
      promotion: promo,
    );
  }

  /// 简易 SAN（仅 UCI + 标记，无 disambiguation）
  String toSimpleLabel() {
    if (flag == MoveFlags.castling) {
      // 白方视角：to col > from col → 王翼（短），否则后翼（长）
      return (to % 8) > (from % 8) ? 'O-O' : 'O-O-O';
    }
    final fromSq = indexToSquare(from);
    final toSq = indexToSquare(to);
    final buf = StringBuffer();
    if (capturedSquare != null) {
      buf.write('${fromSq[0]}x$toSq');
    } else {
      buf.write('$fromSq$toSq');
    }
    if (promotion != null) {
      buf.write('=');
      buf.write(pieceToFenChar(promotion!, sideToMove));
    }
    if (isCheckmate) {
      buf.write('#');
    } else if (givesCheck) {
      buf.write('+');
    }
    return buf.toString();
  }

  /// 棋谱的 sideToMove（用于简单 SAN 输出 + 检查上下文）
  /// 注：完整 SAN 需要带 disambiguation（ranking/file qualifier），
  ///     调用方需用 algebraic.dart 决定；此处只输出最简形式。
  PieceColor get sideToMove => PieceColor.white; // placeholder；UI 层覆盖

  @override
  bool operator ==(Object other) =>
      other is Move &&
      from == other.from &&
      to == other.to &&
      promotion == other.promotion &&
      flag == other.flag &&
      capturedSquare == other.capturedSquare &&
      givesCheck == other.givesCheck &&
      isCheckmate == other.isCheckmate;

  @override
  int get hashCode =>
      Object.hash(from, to, promotion, flag, capturedSquare, givesCheck, isCheckmate);
}
