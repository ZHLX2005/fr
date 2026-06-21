// lib/core/jungle_chess/local/local_match_state.dart
import '../models/game_state.dart';

sealed class LocalMatchState {
  const LocalMatchState();
}

final class LocalIdle extends LocalMatchState {
  const LocalIdle();
}

final class LocalInGame extends LocalMatchState {
  final GameState gameState;
  final int currentPlayerIndex; // 0=蓝色, 1=红色
  const LocalInGame({required this.gameState, required this.currentPlayerIndex});
}

final class LocalFinished extends LocalMatchState {
  final GameState gameState;
  const LocalFinished({required this.gameState});
}
