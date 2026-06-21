// lib/core/jungle_chess/lan/lan_host_protocol_bridge.dart
import 'lan_match_state.dart';
import 'protocol/lan_messages.dart';

LanHostState reduceHostProtocol(LanHostState current, LanRoomEvent event) {
  return switch ((current, event)) {
    (HostWaiting(:final room), ClientJoinRequested(:final clientDeviceId, :final clientAlias)) =>
      HostWaiting(room: room.copyWith(clientDeviceId: clientDeviceId, clientName: clientAlias)),

    (HostInGame(), HostClientLeft()) =>
      const HostError('对手退出了游戏'),

    _ => current,
  };
}
