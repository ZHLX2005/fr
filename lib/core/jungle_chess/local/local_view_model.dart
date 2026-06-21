// lib/core/jungle_chess/local/local_view_model.dart
import 'package:flutter/foundation.dart';
import '../engine/jungle_engine.dart';
import '../models/piece.dart';
import 'local_match_state.dart';
import 'local_match_event.dart';

final class LocalViewModel extends ValueNotifier<LocalMatchState> {
  LocalViewModel() : super(const LocalIdle());

  void dispatch(LocalMatchEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) value = next;
  }

  static LocalMatchState reduce(LocalMatchState state, LocalMatchEvent event) {
    return switch ((state, event)) {
      // LocalIdle → LocalInGame
      (LocalIdle(), LocalStartPressed()) =>
        LocalInGame(
          gameState: JungleEngine.createInitialState(),
          currentPlayerIndex: 0,
        ),

      // LocalInGame → Move
      (LocalInGame(:final gameState), LocalMoveCommitted(:final from, :final to)) => () {
        final next = JungleEngine.movePiece(gameState, from, to);
        if (next == null) return state;
        if (next.isOver) return LocalFinished(gameState: next);
        final nextPlayer = next.currentTurn == PlayerColor.blue ? 0 : 1;
        return LocalInGame(gameState: next, currentPlayerIndex: nextPlayer);
      }(),

      // LocalInGame → Undo (回退两步)
      (LocalInGame(:final gameState), LocalUndoRequested()) => () {
        if (gameState.history.length < 2) return state;
        final prev = JungleEngine.undoMoves(gameState, 2);
        return LocalInGame(gameState: prev, currentPlayerIndex: prev.currentTurn == PlayerColor.blue ? 0 : 1);
      }(),

      // Reset → 回到开局
      (_, LocalResetRequested()) =>
        LocalInGame(
          gameState: JungleEngine.createInitialState(),
          currentPlayerIndex: 0,
        ),

      // Exit
      (_, LocalExitRequested()) => const LocalIdle(),

      _ => state,
    };
  }
}
