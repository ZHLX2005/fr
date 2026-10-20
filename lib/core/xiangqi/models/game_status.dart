// lib/core/xiangqi/models/game_status.dart
//
// 中国象棋终局状态。
//
// 与国际象棋的差异：
//   · 困毙（stale 且对方无着可走）**判负**，不是和棋 —— 这是象棋与
//     国际象棋「僵局算和」最本质的规则差异。
//   · 无「三次重复局面」和棋（中国象棋一般比赛不强制）；和棋来源
//     以双方协商求和为主（服务端 DRAW_OFFER → DRAW_ACCEPT）。
//
// 与国际跳棋的差异：
//   · 保留「将军 / 将杀 / 困毙」三态（象棋有将军概念），跳棋没有。

/// 终局几何类型
enum XiangqiOutcome {  /// 对局进行中
  playing,

  /// 红方胜
  redWins,

  /// 黑方胜
  blackWins,

  /// 和棋
  draw,
}

/// 终局原因（终局时才有意义）
enum XiangqiEndReason {
  /// 未结束
  none,

  /// 将死（对方被将军且无解）
  checkmate,

  /// 困毙（对方未被将军但无着可走 → 判负）
  stalemate,

  /// 认输
  resign,

  /// 双方协商求和
  agreement,

  /// 对方将/帅被吃光（理论上不会发生 —— 走法生成禁止吃将）
  noGeneral,
}

/// 终局状态值对象
class XiangqiStatus {
  final XiangqiOutcome outcome;
  final XiangqiEndReason reason;

  const XiangqiStatus(this.outcome, [this.reason = XiangqiEndReason.none]);

  static const XiangqiStatus playing =
      XiangqiStatus(XiangqiOutcome.playing);

  bool get isOver => outcome != XiangqiOutcome.playing;

  /// 胜方（和棋 / 进行中返回 null）
  XiangqiColorOrNull get winner {
    switch (outcome) {
      case XiangqiOutcome.redWins:
        return XiangqiColorOrNull.red;
      case XiangqiOutcome.blackWins:
        return XiangqiColorOrNull.black;
      case XiangqiOutcome.playing:
      case XiangqiOutcome.draw:
        return XiangqiColorOrNull.none;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is XiangqiStatus &&
      other.outcome == outcome &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(outcome, reason);

  @override
  String toString() => 'XiangqiStatus($outcome, $reason)';
}

/// 胜方标记（避免 game_status 反向依赖 piece.dart 的 enum 细节）
enum XiangqiColorOrNull { none, red, black }
