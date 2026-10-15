// lib/core/draughts/models/game_status.dart
//
// 国际跳棋终局状态。
//
// 与国际象棋的差异：
//   · 没有将军（check）/ 将杀（checkmate）/ 僵局（stalemate）三分 —
//     跳棋里"对方无着可走"直接判负（不是和棋）。
//   · 和棋来源只有：三次重复局面 / 双方仅剩王（王对王）/ 长王步规则。

/// 终局几何类型
enum DraughtsOutcome {
  /// 对局进行中
  playing,

  /// 白方胜
  whiteWins,

  /// 黑方胜
  blackWins,

  /// 和棋
  draw,
}

/// 终局原因（终局时才有意义）
enum DraughtsEndReason {
  /// 未结束
  none,

  /// 吃光对方所有子
  noPieces,

  /// 对方无合法着法（被堵死）
  noMoves,

  /// 认输
  resign,

  /// 三次重复局面
  threefoldRepetition,

  /// 王对王（双方各只剩王）
  kingVsKing,

  /// 长期无吃子/无兵移动（25 回合王步）
  kingMoveLimit,
}

/// 终局状态值对象
class DraughtsStatus {
  final DraughtsOutcome outcome;
  final DraughtsEndReason reason;

  const DraughtsStatus(this.outcome, [this.reason = DraughtsEndReason.none]);

  static const DraughtsStatus playing =
      DraughtsStatus(DraughtsOutcome.playing);

  bool get isOver => outcome != DraughtsOutcome.playing;

  /// 胜方（和棋 / 进行中返回 null）
  DraughtsColorOrNull get winner {
    switch (outcome) {
      case DraughtsOutcome.whiteWins:
        return DraughtsColorOrNull.white;
      case DraughtsOutcome.blackWins:
        return DraughtsColorOrNull.black;
      default:
        return DraughtsColorOrNull.none;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is DraughtsStatus &&
      other.outcome == outcome &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(outcome, reason);

  @override
  String toString() => 'DraughtsStatus($outcome, $reason)';
}

/// 胜方标记（避免 game_status 反向依赖 piece.dart）
enum DraughtsColorOrNull { none, white, black }
