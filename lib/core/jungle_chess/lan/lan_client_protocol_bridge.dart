// lib/core/jungle_chess/lan/lan_client_protocol_bridge.dart
import 'lan_match_state.dart';
import 'protocol/lan_messages.dart';

LanClientState reduceClientProtocol(LanClientState current, LanRoomEvent event) {
  return switch ((current, event)) {
    (ClientJoining(:final targetRoom), ClientJoinResult(:final accepted)) =>
      accepted ? ClientWaiting(room: targetRoom) : const ClientIdle(),

    (ClientInGame(), ClientDisconnectedProtocol(:final message)) =>
      ClientDisconnected(message: message),

    _ => current,
  };
}
