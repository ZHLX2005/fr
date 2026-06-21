// lib/core/jungle_chess/lan/lan_client_view_model.dart
import 'package:flutter/foundation.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_client_protocol_bridge.dart';
import 'protocol/lan_messages.dart';

class LanClientViewModel extends ValueNotifier<LanClientState> {
  LanClientViewModel() : super(const ClientIdle());

  void dispatch(LanClientEvent event) {
    final next = reduce(value, event);
    if (!identical(next, value)) value = next;
  }

  void dispatchProtocol(LanRoomEvent event) {
    value = reduceClientProtocol(value, event);
  }

  static LanClientState reduce(LanClientState state, LanClientEvent event) {
    return switch ((state, event)) {
      (ClientIdle(), ClientJoinRoom(:final room)) =>
        ClientJoining(targetRoom: room),

      (_, ClientExit()) => const ClientIdle(),

      _ => state,
    };
  }
}
