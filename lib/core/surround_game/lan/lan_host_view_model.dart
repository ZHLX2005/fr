import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/game_engine.dart';
import '../local/local_match_state.dart';
import '../models/game_room.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';
import 'lan_match_event.dart';
import 'lan_match_state.dart';

final class LanHostViewModel extends ValueNotifier<LanHostState> {
  Timer? _countdownTimer;

  LanHostViewModel() : super(const HostLobby());

  void dispatch(LanHostEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) {
      value = next;
    }
  }

  LanHostState reduce(LanHostState s, LanHostEvent e) {
    return switch (e) {
      HostCreateRoomPressed() when s is HostLobby =>
        HostWaiting(GameRoom.placeholder(
          roomId: 'room-${DateTime.now().millisecondsSinceEpoch}',
        )),
      HostCreateRoomWithRoom(:final room) when s is HostLobby =>
        HostWaiting(room),
      HostClientJoined(:final clientId, :final clientName)
          when s is HostWaiting =>
        HostWaiting(s.room.copyWith(
          clientId: clientId,
          clientName: clientName,
        )),
      HostStartGamePressed() when s is HostWaiting =>
        _startCountdown(s.room),
      HostTick() when s is HostCountdown =>
        s.secondsLeft > 1
            ? HostCountdown(s.room, s.secondsLeft - 1)
            : HostInGame(QuoridorEngine.initialize(), s.room),
      HostMoveReceived(:final moveData) when s is HostInGame =>
        _applyAndCheck(s, moveData),
      HostMoveCommitted(:final moveData) when s is HostInGame =>
        _applyAndCheck(s, moveData),
      HostAbortGame() when s is HostError => value,
      HostAbortGame() => s,
      HostRetryPressed() when s is HostError =>
        s.previous ?? const HostLobby(),
      _ => s,
    };
  }

  HostCountdown _startCountdown(GameRoom room) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      dispatch(const HostTick());
    });
    return HostCountdown(room, 3);
  }

  LanHostState _applyAndCheck(
    HostInGame s,
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
    if (next.status == GameStatus.running) return HostInGame(next, s.room);
    // Determine result
    final gameResult = next.status == GameStatus.topWin
        ? GameResult.topWin
        : next.status == GameStatus.bottomWin
            ? GameResult.bottomWin
            : GameResult.draw;
    return HostFinished(next, s.room, gameResult);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}
