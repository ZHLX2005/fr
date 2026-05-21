/// 游戏阶段 — 状态机，替代散落 bool
enum GamePhase {
  /// 水动画入场
  waterEnter,

  /// 倒计时
  countdown,

  /// 游戏进行中
  playing,

  /// 暂停中
  paused,

  /// 退场动画中
  exiting,
}
