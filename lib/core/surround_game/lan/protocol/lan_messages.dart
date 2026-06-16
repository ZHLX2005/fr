// lib/core/surround_game/lan/protocol/lan_messages.dart
//
// 局域网协议消息 — sealed class 形式，编译期穷尽。
// 序列化统一带 'type' 字段做反分发，未知 type 抛 FormatException。
//
// 序列化格式：
//   { 'type': '<event-name>', ...payload }

import '../game_room.dart';

sealed class LanRoomEvent {
  const LanRoomEvent();

  String get type;
  Map<String, dynamic> toJson();

  static LanRoomEvent fromJson(Map<String, dynamic> json) {
    final t = json['type'] as String?;
    return switch (t) {
      'HostRoomAnnounced' => HostRoomAnnounced(
          room: GameRoom.fromJson(
              (json['room'] as Map).cast<String, dynamic>()),
          hostDeviceId: json['hostDeviceId'] as String,
          hostAlias: json['hostAlias'] as String,
        ),
      'HostRoomClosed' => HostRoomClosed(
          roomId: json['roomId'] as String,
        ),
      'ClientJoinRequested' => ClientJoinRequested(
          clientDeviceId: json['clientDeviceId'] as String,
          clientAlias: json['clientAlias'] as String,
          roomId: json['roomId'] as String,
        ),
      'ClientJoinResult' => ClientJoinResult(
          roomId: json['roomId'] as String,
          clientDeviceId: json['clientDeviceId'] as String,
          accepted: json['accepted'] as bool,
          reason: json['reason'] as String?,
        ),
      _ => throw FormatException('Unknown LanRoomEvent type: $t'),
    };
  }
}

/// Host → 广播：建了房间
class HostRoomAnnounced extends LanRoomEvent {
  HostRoomAnnounced({
    required this.room,
    required this.hostDeviceId,
    required this.hostAlias,
  });

  final GameRoom room;
  final String hostDeviceId;
  final String hostAlias;

  @override
  String get type => 'HostRoomAnnounced';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'room': room.toJson(),
        'hostDeviceId': hostDeviceId,
        'hostAlias': hostAlias,
      };
}

/// Host → 广播：关房。由 LanHostGamePage.dispose（退出游戏）与
/// LanRoomPage.dispose（放弃建房）经 LanServiceAdapter.stopRoom 发出。
class HostRoomClosed extends LanRoomEvent {
  HostRoomClosed({required this.roomId});

  final String roomId;

  @override
  String get type => 'HostRoomClosed';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'roomId': roomId,
      };
}

/// Client → Host：请求加入
class ClientJoinRequested extends LanRoomEvent {
  ClientJoinRequested({
    required this.clientDeviceId,
    required this.clientAlias,
    required this.roomId,
  });

  final String clientDeviceId;
  final String clientAlias;
  final String roomId;

  @override
  String get type => 'ClientJoinRequested';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'clientDeviceId': clientDeviceId,
        'clientAlias': clientAlias,
        'roomId': roomId,
      };
}

/// Host → Client：加入结果
class ClientJoinResult extends LanRoomEvent {
  ClientJoinResult({
    required this.roomId,
    required this.clientDeviceId,
    required this.accepted,
    this.reason,
  });

  final String roomId;
  final String clientDeviceId;
  final bool accepted;
  final String? reason;

  @override
  String get type => 'ClientJoinResult';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'roomId': roomId,
        'clientDeviceId': clientDeviceId,
        'accepted': accepted,
        if (reason != null) 'reason': reason,
      };
}

/// Host 端设备掉线事件（deviceLost 触发）— 作为 LanRoomEvent 子类，
/// 让 bridge 的 switch 走统一分发路径。
/// 定义在 lan_messages.dart 内（与 LanRoomEvent 同 library）以满足 sealed 约束。
/// 与 lan_match_event.dart 中的 HostClientLeft extends LanHostEvent 不冲突 —
/// 两者父类不同，调用方按需 import。
class HostClientLeft extends LanRoomEvent {
  HostClientLeft();
  @override
  String get type => 'HostClientLeft';
  @override
  Map<String, dynamic> toJson() => {'type': type};
}

/// Client 端设备掉线事件（deviceLost 触发）— 作为 LanRoomEvent 子类。
class ClientDisconnectedProtocol extends LanRoomEvent {
  ClientDisconnectedProtocol();
  @override
  String get type => 'ClientDisconnectedProtocol';
  @override
  Map<String, dynamic> toJson() => {'type': type};
}
