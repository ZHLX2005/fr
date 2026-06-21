// lib/core/jungle_chess/lan/lan_host_view_model.dart
import 'package:flutter/foundation.dart';
import '../engine/jungle_engine.dart';
import 'game_room.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_protocol_bridge.dart';
import 'protocol/lan_messages.dart';

class LanHostViewModel extends ValueNotifier<LanHostState> {
  LanHostViewModel() : super(const HostLobby());

  void dispatch(LanHostEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) value = next;
  }

  void dispatchProtocol(LanRoomEvent event) {
    value = reduceHostProtocol(value, event);
  }

  static LanHostState reduce(LanHostState state, LanHostEvent event) {
    return switch ((state, event)) {
      (HostLobby(), HostCreateRoom(:final roomId, :final hostName)) =>
        HostWaiting(room: GameRoom(roomId: roomId, hostDeviceId: '', hostName: hostName)),

      (HostWaiting(:final room), HostStartGame()) =>
        HostCountdown(room: room, secondsLeft: 3),

      (HostCountdown(:final room), HostCountdownTick(secondsLeft: final newSec)) =>
        newSec > 0
          ? HostCountdown(room: room, secondsLeft: newSec)
          : HostInGame(gameState: JungleEngine.createInitialState()),

      (HostInGame(:final gameState), HostMoveCommitted(:final from, :final to)) => () {
        final next = JungleEngine.movePiece(gameState, from, to);
        if (next == null) return state;
        if (next.isOver) return HostFinished(gameState: next);
        return HostInGame(gameState: next);
      }(),

      (HostFinished(), HostStartGame()) =>
        HostInGame(gameState: JungleEngine.createInitialState()),

      (_, HostExit()) => const HostLobby(),

      _ => state,
    };
  }
}
