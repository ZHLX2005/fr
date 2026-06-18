// lib/core/surround_game/lan/lan_host_protocol_bridge.dart
//
// Host 端协议事件 → 状态机迁移纯函数。
// 直接消费 LanRoomEvent，不引入额外抽象。
//
// HostClientLeft 已定义在 lan_messages.dart（同 library，sealed 约束）。

import 'lan_match_state.dart';
import 'protocol/lan_messages.dart';

LanHostState reduceHostProtocol(LanHostState current, LanRoomEvent event) {
  return switch ((current, event)) {
    (HostWaiting(:final room), ClientJoinRequested e) => HostWaiting(
        room.copyWith(
          clientId: e.clientDeviceId,
          clientName: e.clientAlias,
        ),
      ),
    (HostInGame(), HostClientLeft()) => HostError(
        '对手掉线',
        previous: current,
      ),
    _ => current,
  };
}
