import '../surround_game_constants.dart';

/// 游戏事件模型
///
/// sealed class 确保事件类型是穷举的（Dart 3 feature）。
/// 配合 switch 的 exhaustive 检查，UI 层处理事件时不会漏分支。
///
/// 本轮在引擎层产生事件，但不强依赖（引擎纯函数返回 new state，
/// 事件仅用于日志/动画触发，非必要）。
sealed class GameEvent {
  const GameEvent();
}

/// 棋子从 fromCellId 移动到 toCellId
class PieceMovedEvent extends GameEvent {
  final int fromCellId;
  final int toCellId;
  final bool isTopPlayer;

  const PieceMovedEvent({
    required this.fromCellId,
    required this.toCellId,
    required this.isTopPlayer,
  });

  @override
  String toString() =>
      'PieceMoved(${isTopPlayer ? "top" : "bottom"}: $fromCellId → $toCellId)';
}

/// 在格点 (x, y) 放置了 orientation 方向的墙壁
class WallPlacedEvent extends GameEvent {
  final int x;
  final int y;
  final WallOrientation orientation;
  final bool isTopPlayer;

  const WallPlacedEvent({
    required this.x,
    required this.y,
    required this.orientation,
    required this.isTopPlayer,
  });

  @override
  String toString() =>
      'WallPlaced(${isTopPlayer ? "top" : "bottom"}: ($x,$y) $orientation)';
}

/// 游戏结束
class GameOverEvent extends GameEvent {
  final GameStatus status; // topWin / bottomWin / draw

  const GameOverEvent({required this.status});

  @override
  String toString() => 'GameOver($status)';
}
