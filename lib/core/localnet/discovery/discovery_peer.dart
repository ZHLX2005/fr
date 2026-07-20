import '../transport/transport_kind.dart';

/// 发现的对端设备 — LAN/Relay 统一模型
class DiscoveryPeer {
  const DiscoveryPeer({
    required this.deviceId,
    required this.alias,
    required this.address,
    required this.kind,
    required this.lastSeen,
  });

  final String deviceId;
  final String alias;
  final String address;
  final TransportKind kind;
  final DateTime lastSeen;
}
