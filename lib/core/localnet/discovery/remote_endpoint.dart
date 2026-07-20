import '../transport/transport_kind.dart';

/// 远端设备端点 — DiscoveryService 发现的最小单元
///
/// LAN 模式下 address 形如 "192.168.1.5:53317"（HTTP P2P 目标）；
/// Relay 模式下 address 是中继服务器分配的 ws-session id。
class RemoteEndpoint {
  const RemoteEndpoint({
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