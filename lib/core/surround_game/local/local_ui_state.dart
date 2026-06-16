import '../models/game_state.dart';
import '../surround_game_constants.dart';
import '../widgets/touch_controller.dart';

/// 单机热座的 UI 交互态 — 持有 GameState + TouchController 引用。
class LocalUiState {
  final GameState gameState;
  final TouchController touch;

  const LocalUiState({
    required this.gameState,
    required this.touch,
  });

  bool get isTopTurn => gameState.currentPlayerIsTop;

  int get remainingWalls =>
      SurroundGameConstants.wallCountPerPlayer -
      (gameState.currentPlayerIsTop
          ? gameState.topWallsPlaced
          : gameState.bottomWallsPlaced);

  bool get canPlaceWall => remainingWalls > 0;
}
