/// 游戏事件模型
///
/// sealed class 确保事件类型是穷举的（Dart 3）。
sealed class GameEvent {}

/// 碰撞事件：玩家撞墙或撞轨迹
class CollisionEvent extends GameEvent {
  final String playerId;
  CollisionEvent(this.playerId);
}

/// 得分事件：某位玩家因对方碰撞而得分
class ScoreEvent extends GameEvent {
  final String playerId;
  final int newScore;
  ScoreEvent(this.playerId, this.newScore);
}

/// 游戏结束事件
class GameOverEvent extends GameEvent {
  final String winnerId;
  final int finalScoreHost;
  final int finalScoreClient;
  GameOverEvent({
    required this.winnerId,
    required this.finalScoreHost,
    required this.finalScoreClient,
  });
}

/// 回合重置事件（得分后清空棋盘）
class ResetRoundEvent extends GameEvent {}
