import '../models/game_state.dart';

/// 单局结果枚举
enum GameResult { topWin, bottomWin, draw, abandoned }

/// 单机热座匹配状态 — sealed class 层次结构
sealed class LocalMatchState {
  const LocalMatchState();
}

class LocalIdle extends LocalMatchState {
  const LocalIdle();
}

class LocalInGame extends LocalMatchState {
  const LocalInGame(this.gameState);

  final GameState gameState;
}

class LocalFinished extends LocalMatchState {
  const LocalFinished(this.finalState, this.result);

  final GameState finalState;
  final GameResult result;
}
