import 'package:shared_preferences/shared_preferences.dart';

class LocalnetConfig {
  static const String _keyDeviceAlias = 'localnet_device_alias';
  static const String _keyHttpEnabled = 'localnet_http_enabled';
  static const String _keyMulticastEnabled = 'localnet_multicast_enabled';
  static const String _keyPort = 'localnet_port';

  final String deviceAlias;
  final bool httpEnabled;
  final bool multicastEnabled;
  final int port;

  const LocalnetConfig({
    this.deviceAlias = 'Flutter Device',
    this.httpEnabled = true,
    this.multicastEnabled = true,
    this.port = 53317,
  });

  LocalnetConfig copyWith({
    String? deviceAlias,
    bool? httpEnabled,
    bool? multicastEnabled,
    int? port,
  }) {
    return LocalnetConfig(
      deviceAlias: deviceAlias ?? this.deviceAlias,
      httpEnabled: httpEnabled ?? this.httpEnabled,
      multicastEnabled: multicastEnabled ?? this.multicastEnabled,
      port: port ?? this.port,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceAlias': deviceAlias,
        'httpEnabled': httpEnabled,
        'multicastEnabled': multicastEnabled,
        'port': port,
      };

  factory LocalnetConfig.fromJson(Map<String, dynamic> json) {
    return LocalnetConfig(
      deviceAlias: json['deviceAlias'] as String? ?? 'Flutter Device',
      httpEnabled: json['httpEnabled'] as bool? ?? true,
      multicastEnabled: json['multicastEnabled'] as bool? ?? true,
      port: json['port'] as int? ?? 53317,
    );
  }

  static Future<LocalnetConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalnetConfig(
      deviceAlias: prefs.getString(_keyDeviceAlias) ?? 'Flutter Device',
      httpEnabled: prefs.getBool(_keyHttpEnabled) ?? true,
      multicastEnabled: prefs.getBool(_keyMulticastEnabled) ?? true,
      port: prefs.getInt(_keyPort) ?? 53317,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceAlias, deviceAlias);
    await prefs.setBool(_keyHttpEnabled, httpEnabled);
    await prefs.setBool(_keyMulticastEnabled, multicastEnabled);
    await prefs.setInt(_keyPort, port);
  }

  @override
  String toString() =>
      'LocalnetConfig(alias: $deviceAlias, http: $httpEnabled, multicast: $multicastEnabled, port: $port)';
}
