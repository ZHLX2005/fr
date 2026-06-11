import 'dart:math';
import '../../surround_game_constants.dart';
import '../../_legacy/models/game_state.dart';
import '../../_legacy/models/game_event.dart';
import 'collision_detector.dart';

/// 游戏引擎结果
class EngineResult {
  final GameState newState;
  final List<GameEvent> events;

  const EngineResult({required this.newState, required this.events});
}

/// 围追堵截游戏引擎 — 纯函数，无副作用
class GameEngine {
  GameEngine._();

  /// 初始化新棋盘
  static GameState initialize() => GameState.initialize();

  /// 重置一轮（得分后清空轨迹，双方回到起点）
  static GameState _resetRound(GameState state) {
    final fresh = GameState.initialize();
    return state.copyWith(
      board: fresh.board,
      hostPos: fresh.hostPos,
      clientPos: fresh.clientPos,
    );
  }

  /// 执行一步
  static EngineResult step(
    GameState state,
    Direction hostMove,
    Direction clientMove, {
    String hostId = 'host',
    String clientId = 'client',
  }) {
    final events = <GameEvent>[];
    final board = state.board.map((row) => [...row]).toList();
    int hostScore = state.hostScore;
    int clientScore = state.clientScore;

    // 在旧位置留下轨迹
    board[state.hostPos.x][state.hostPos.y] = CellState.hostTrail;
    board[state.clientPos.x][state.clientPos.y] = CellState.clientTrail;

    // 计算新位置
    final newHostPos = _movePos(state.hostPos, hostMove);
    final newClientPos = _movePos(state.clientPos, clientMove);

    // 检测碰撞
    bool hostCollided = CollisionDetector.wouldCollide(board, newHostPos);
    bool clientCollided = CollisionDetector.wouldCollide(board, newClientPos);

    // 处理碰撞
    if (hostCollided) {
      events.add(CollisionEvent(hostId));
      clientScore++;
      events.add(ScoreEvent(clientId, clientScore));
    }
    if (clientCollided) {
      events.add(CollisionEvent(clientId));
      hostScore++;
      events.add(ScoreEvent(hostId, hostScore));
    }

    // 有人碰撞 → 检查胜利条件或重置回合
    if (hostCollided || clientCollided) {
      // 检查是否有人胜出
      if (hostScore >= SurroundGameConstants.winScore) {
        events.add(GameOverEvent(
          winnerId: hostId,
          finalScoreHost: hostScore,
          finalScoreClient: clientScore,
        ));
        return EngineResult(
          newState: state.copyWith(
            board: board,
            hostScore: hostScore,
            clientScore: clientScore,
            stepNumber: state.stepNumber + 1,
            isGameOver: true,
            winnerId: hostId,
          ),
          events: events,
        );
      }
      if (clientScore >= SurroundGameConstants.winScore) {
        events.add(GameOverEvent(
          winnerId: clientId,
          finalScoreHost: hostScore,
          finalScoreClient: clientScore,
        ));
        return EngineResult(
          newState: state.copyWith(
            board: board,
            hostScore: hostScore,
            clientScore: clientScore,
            stepNumber: state.stepNumber + 1,
            isGameOver: true,
            winnerId: clientId,
          ),
          events: events,
        );
      }

      // 无人胜出 → 重置棋盘，位置回到起点
      final next = state.copyWith(
        board: board,
        hostScore: hostScore,
        clientScore: clientScore,
        stepNumber: state.stepNumber + 1,
      );
      final reset = _resetRound(next);
      events.add(ResetRoundEvent());
      return EngineResult(newState: reset, events: events);
    }

    // 正常移动（无人碰撞）
    return EngineResult(
      newState: state.copyWith(
        board: board,
        hostPos: newHostPos,
        clientPos: newClientPos,
        stepNumber: state.stepNumber + 1,
      ),
      events: events,
    );
  }

  static Point<int> _movePos(Point<int> pos, Direction dir) {
    switch (dir) {
      case Direction.up:
        return Point<int>(pos.x - 1, pos.y);
      case Direction.down:
        return Point<int>(pos.x + 1, pos.y);
      case Direction.left:
        return Point<int>(pos.x, pos.y - 1);
      case Direction.right:
        return Point<int>(pos.x, pos.y + 1);
    }
  }
}
