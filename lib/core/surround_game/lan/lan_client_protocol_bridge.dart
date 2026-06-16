// lib/core/surround_game/lan/lan_client_protocol_bridge.dart
//
// Client 端协议事件 → 状态机迁移纯函数。
//
// ClientDisconnectedProtocol 已定义在 lan_messages.dart（同 library，sealed 约束）。

import 'lan_match_state.dart';
import 'protocol/lan_messages.dart';

LanClientState reduceClientProtocol(
  LanClientState current,
  LanRoomEvent event,
) {
  return switch ((current, event)) {
    (ClientJoining(:final targetRoom), ClientJoinResult(:final accepted)) => accepted
        ? ClientWaiting(targetRoom)
        : const ClientIdle(),
    (ClientInGame(), ClientDisconnectedProtocol()) => const ClientDisconnected(),
    _ => current,
  };
}
