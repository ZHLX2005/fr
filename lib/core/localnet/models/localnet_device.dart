enum DeviceType { mobile, desktop, web }

class LocalnetDevice {
  final String id;
  final String alias;
  final String ip;
  final int port;
  final DeviceType deviceType;
  final String? deviceModel;
  final DateTime lastSeen;

  LocalnetDevice({
    required this.id,
    required this.alias,
    required this.ip,
    required this.port,
    required this.deviceType,
    this.deviceModel,
    required this.lastSeen,
  });

  factory LocalnetDevice.fromJson(Map<String, dynamic> json, String ip) {
    return LocalnetDevice(
      id: json['id'] as String? ?? ip,
      alias: json['alias'] as String? ?? 'Unknown',
      ip: ip,
      port: json['port'] as int? ?? 53317,
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == (json['deviceType'] as String?),
        orElse: () => DeviceType.desktop,
      ),
      deviceModel: json['deviceModel'] as String?,
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'alias': alias,
        'ip': ip,
        'port': port,
        'deviceType': deviceType.name,
        'deviceModel': deviceModel,
      };

  static LocalnetDevice fromMulticast(Map<String, dynamic> json, String ip) {
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
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toMulticastJson(String fingerprint) => {
        'alias': alias,
        'version': '1.0',
        'deviceType': deviceType.name,
        'fingerprint': fingerprint,
        'port': port,
        'announce': true,
      };
}
