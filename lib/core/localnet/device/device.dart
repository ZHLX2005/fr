/// 设备信息
class Device {
  const Device({
    required this.deviceId,
    required this.alias,
    required this.ip,
    required this.port,
    required this.lastSeen,
    required this.extras,
  });

  final String deviceId;
  final String alias;
  final String ip;
  final int port;
  final DateTime lastSeen;
  final Map<String, String> extras;

  /// 心跳是否超时（基于给定 timeout）
  bool isStale({required Duration timeout, DateTime? now}) {
    final n = now ?? DateTime.now();
    return n.difference(lastSeen) > timeout;
  }

  Device copyWith({
    String? alias,
    String? ip,
    int? port,
    DateTime? lastSeen,
    Map<String, String>? extras,
  }) {
    return Device(
      deviceId: deviceId,
      alias: alias ?? this.alias,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      extras: extras ?? this.extras,
    );
  }
}
