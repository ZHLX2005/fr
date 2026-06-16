import '../surround_game_constants.dart';

/// 单机热座匹配事件 — sealed class 层次结构
sealed class LocalMatchEvent {
  const LocalMatchEvent();
}

class LocalStartPressed extends LocalMatchEvent {
  const LocalStartPressed();
}

/// 玩家已确认的操作（走棋或放墙），由 ViewModel 解析为引擎调用
class LocalMoveCommitted extends LocalMatchEvent {
  const LocalMoveCommitted({
    required this.targetCellId,
    this.wallX,
    this.wallY,
    this.wallOrientation,
  });

  /// 走棋目标格子 cellId（走棋时使用）
  final int targetCellId;

  /// 放墙坐标 x（放墙时使用，0-7）
  final int? wallX;

  /// 放墙坐标 y（放墙时使用，0-7）
  final int? wallY;

  /// 放墙方向（放墙时使用）
  final WallOrientation? wallOrientation;

  bool get isWall => wallX != null && wallY != null && wallOrientation != null;
}

class LocalUndoRequested extends LocalMatchEvent {
  const LocalUndoRequested();
}

class LocalResetRequested extends LocalMatchEvent {
  const LocalResetRequested();
}

class LocalExitRequested extends LocalMatchEvent {
  const LocalExitRequested();
}
