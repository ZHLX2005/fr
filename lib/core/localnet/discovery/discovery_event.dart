import 'discovery_peer.dart';

/// 发现层事件 — LAN/Relay 统一的 sealed 事件模型
sealed class DiscoveryEvent {
  const DiscoveryEvent();
}

/// 发现新设备（LAN：UDP 心跳；Relay：对端 WS 连接/房间加入）
class PeerFound extends DiscoveryEvent {
  const PeerFound(this.peer);
  final DiscoveryPeer peer;
}

/// 设备离线（LAN：超时未心跳；Relay：WS 断开）
class PeerLost extends DiscoveryEvent {
  const PeerLost(this.deviceId);
  final String deviceId;
}

/// 房间创建成功（仅 Relay）
class RoomCreated extends DiscoveryEvent {
  const RoomCreated({required this.roomCode, this.hostAlias});
  final String roomCode;
  final String? hostAlias;
}

/// 房间加入成功（仅 Relay）
class RoomJoined extends DiscoveryEvent {
  const RoomJoined({required this.roomCode, required this.host});
  final String roomCode;
  final DiscoveryPeer host;
}

/// 房间已满（仅 Relay）
class RoomFull extends DiscoveryEvent {
  const RoomFull(this.roomCode);
  final String roomCode;
}

/// 房间不存在（仅 Relay）
class RoomNotFound extends DiscoveryEvent {
  const RoomNotFound(this.roomCode);
  final String roomCode;
}

/// 房间已离开
class RoomLeft extends DiscoveryEvent {
  const RoomLeft(this.roomCode);
  final String roomCode;
}
