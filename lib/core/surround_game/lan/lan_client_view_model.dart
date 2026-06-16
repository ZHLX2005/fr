import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/game_engine.dart';
import '../local/local_match_state.dart';
import '../models/game_room.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';
import 'lan_match_event.dart';
import 'lan_match_state.dart';

final class LanClientViewModel extends ValueNotifier<LanClientState> {
  Timer? _countdownTimer;

  LanClientViewModel() : super(const ClientIdle());

  void dispatch(LanClientEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) {
      value = next;
    }
  }

  LanClientState reduce(LanClientState s, LanClientEvent e) {
    return switch (e) {
      ClientJoinPressed(:final room) when s is ClientIdle =>
        ClientJoining(room),
      ClientJoinAccepted(:final room) when s is ClientJoining =>
        ClientWaiting(room),
      ClientJoinRejected() when s is ClientJoining => const ClientIdle(),
      HostStartedCountdown(:final secondsLeft) when s is ClientWaiting =>
        _startCountdown(s.room, secondsLeft),
      ClientTick() when s is ClientCountdown =>
        s.secondsLeft > 1
            ? ClientCountdown(s.room, s.secondsLeft - 1)
            : ClientInGame(QuoridorEngine.initialize(), s.room),
      ClientMoveCommitted(:final moveData) when s is ClientInGame =>
        _applyAndCheck(s, moveData),
      HostStatePushed(:final gameState) when s is ClientInGame =>
        ClientInGame(gameState, s.room),
      ClientReconnectPressed() when s is ClientDisconnected =>
        const ClientIdle(),
      _ => s,
    };
  }

  ClientCountdown _startCountdown(GameRoom room, int secondsLeft) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      dispatch(const ClientTick());
    });
    return ClientCountdown(room, secondsLeft);
  }

  LanClientState _applyAndCheck(
    ClientInGame s,
    (int targetCellId, int? wallX, int? wallY,
        WallOrientation? wallOrientation) move,
  ) {
    GameState? result;
    if (move.$2 != null && move.$4 != null) {
      result =
          QuoridorEngine.placeWall(s.gameState, move.$2!, move.$3!, move.$4!);
    } else {
      result = QuoridorEngine.movePiece(s.gameState, move.$1);
    }
    if (result == null) return s;
    final next = QuoridorEngine.switchTurn(result);
    if (next.status == GameStatus.running) return ClientInGame(next, s.room);
    final gameResult = next.status == GameStatus.topWin
        ? GameResult.topWin
        : next.status == GameStatus.bottomWin
            ? GameResult.bottomWin
            : GameResult.draw;
    return ClientFinished(next, s.room, gameResult);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}
