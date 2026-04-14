enum DeviceType { mobile, desktop, web }

class LocalnetDevice {
  final String id; // fingerprint
  final String alias;
  final String ip;
  final int port;
  final DeviceType deviceType;
  final String? deviceModel;
  final String version;
  final DateTime lastSeen;

  LocalnetDevice({
    required this.id,
    required this.alias,
    required this.ip,
    required this.port,
    required this.deviceType,
    this.deviceModel,
    required this.version,
    required this.lastSeen,
  });

  factory LocalnetDevice.fromMulticast(Map<String, dynamic> json, String ip) {
    return LocalnetDevice(
      id: json['fingerprint'] as String? ?? ip,
      alias: json['alias'] as String? ?? 'Unknown',
      ip: ip,
      port: json['port'] as int? ?? 53317,
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == (json['deviceType'] as String?),
        orElse: () => DeviceType.desktop,
      ),
      deviceModel: json['deviceModel'] as String?,
      version: json['version'] as String? ?? '1.0',
      lastSeen: DateTime.now(),
    );
  }

  factory LocalnetDevice.fromRegister(Map<String, dynamic> json, String ip) {
    return LocalnetDevice(
      id: json['fingerprint'] as String? ?? ip,
      alias: json['alias'] as String? ?? 'Unknown',
      ip: ip,
      port: json['port'] as int? ?? 53317,
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == (json['deviceType'] as String?),
        orElse: () => DeviceType.desktop,
      ),
      deviceModel: json['deviceModel'] as String?,
      version: json['version'] as String? ?? '1.0',
      lastSeen: DateTime.now(),
    );
  }

  LocalnetDevice copyWith({DateTime? lastSeen}) {
    return LocalnetDevice(
      id: id,
      alias: alias,
      ip: ip,
      port: port,
      deviceType: deviceType,
      deviceModel: deviceModel,
      version: version,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
