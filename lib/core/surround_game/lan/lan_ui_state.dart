import '../models/game_state.dart';
import '../surround_game_constants.dart';
import '../widgets/touch_controller.dart';

class LanUiState {
  final GameState gameState;
  final TouchController touch;
  final bool inputDisabled;

  const LanUiState({
    required this.gameState,
    required this.touch,
    this.inputDisabled = false,
  });

  bool get isTopTurn => gameState.currentPlayerIsTop;
  bool get canPlaceWall => remainingWalls > 0 && !inputDisabled;

  int get remainingWalls =>
      SurroundGameConstants.wallCountPerPlayer -
      (gameState.currentPlayerIsTop
          ? gameState.topWallsPlaced
          : gameState.bottomWallsPlaced);
}
