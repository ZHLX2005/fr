import 'package:shared_preferences/shared_preferences.dart';

import 'localnet_constants.dart';

class LocalnetConfig {
  static const String _keyDeviceAlias = 'localnet_device_alias';
  static const String _keyHttpEnabled = 'localnet_http_enabled';
  static const String _keyMulticastEnabled = 'localnet_multicast_enabled';
  static const String _keyUdpBroadcastEnabled =
      'localnet_udp_broadcast_enabled';
  static const String _keyUdpListenerEnabled = 'localnet_udp_listener_enabled';
  static const String _keyHttpServerEnabled = 'localnet_http_server_enabled';
  static const String _keyPort = 'localnet_port';

  final String deviceAlias;
  final bool httpEnabled;
  final bool multicastEnabled;
  final bool udpBroadcastEnabled;
  final bool udpListenerEnabled;
  final bool httpServerEnabled;
  final int port;

  const LocalnetConfig({
    this.deviceAlias = LocalnetConstants.defaultDeviceAlias,
    this.httpEnabled = true,
    this.multicastEnabled = true,
    this.udpBroadcastEnabled = true,
    this.udpListenerEnabled = true,
    this.httpServerEnabled = true,
    this.port = LocalnetConstants.defaultPort,
  });

  LocalnetConfig copyWith({
    String? deviceAlias,
    bool? httpEnabled,
    bool? multicastEnabled,
    bool? udpBroadcastEnabled,
    bool? udpListenerEnabled,
    bool? httpServerEnabled,
    int? port,
  }) {
    return LocalnetConfig(
      deviceAlias: deviceAlias ?? this.deviceAlias,
      httpEnabled: httpEnabled ?? this.httpEnabled,
      multicastEnabled: multicastEnabled ?? this.multicastEnabled,
      udpBroadcastEnabled: udpBroadcastEnabled ?? this.udpBroadcastEnabled,
      udpListenerEnabled: udpListenerEnabled ?? this.udpListenerEnabled,
      httpServerEnabled: httpServerEnabled ?? this.httpServerEnabled,
      port: port ?? this.port,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceAlias': deviceAlias,
    'httpEnabled': httpEnabled,
    'multicastEnabled': multicastEnabled,
    'udpBroadcastEnabled': udpBroadcastEnabled,
    'udpListenerEnabled': udpListenerEnabled,
    'httpServerEnabled': httpServerEnabled,
    'port': port,
  };

  factory LocalnetConfig.fromJson(Map<String, dynamic> json) {
    return LocalnetConfig(
      deviceAlias:
          json['deviceAlias'] as String? ??
          LocalnetConstants.defaultDeviceAlias,
      httpEnabled: json['httpEnabled'] as bool? ?? true,
      multicastEnabled: json['multicastEnabled'] as bool? ?? true,
      udpBroadcastEnabled: json['udpBroadcastEnabled'] as bool? ?? true,
      udpListenerEnabled: json['udpListenerEnabled'] as bool? ?? true,
      httpServerEnabled: json['httpServerEnabled'] as bool? ?? true,
      port: json['port'] as int? ?? LocalnetConstants.defaultPort,
    );
  }

  static Future<LocalnetConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalnetConfig(
      deviceAlias:
          prefs.getString(_keyDeviceAlias) ??
          LocalnetConstants.defaultDeviceAlias,
      httpEnabled: prefs.getBool(_keyHttpEnabled) ?? true,
      multicastEnabled: prefs.getBool(_keyMulticastEnabled) ?? true,
      udpBroadcastEnabled: prefs.getBool(_keyUdpBroadcastEnabled) ?? true,
      udpListenerEnabled: prefs.getBool(_keyUdpListenerEnabled) ?? true,
      httpServerEnabled: prefs.getBool(_keyHttpServerEnabled) ?? true,
      port: prefs.getInt(_keyPort) ?? LocalnetConstants.defaultPort,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceAlias, deviceAlias);
    await prefs.setBool(_keyHttpEnabled, httpEnabled);
    await prefs.setBool(_keyMulticastEnabled, multicastEnabled);
    await prefs.setBool(_keyUdpBroadcastEnabled, udpBroadcastEnabled);
    await prefs.setBool(_keyUdpListenerEnabled, udpListenerEnabled);
    await prefs.setBool(_keyHttpServerEnabled, httpServerEnabled);
    await prefs.setInt(_keyPort, port);
  }

  @override
  String toString() =>
      'LocalnetConfig(alias: $deviceAlias, http: $httpEnabled, multicast: $multicastEnabled, '
      'udpBroadcast: $udpBroadcastEnabled, udpListener: $udpListenerEnabled, '
      'httpServer: $httpServerEnabled, port: $port)';
}
