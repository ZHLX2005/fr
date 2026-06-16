import '../transport/transport_config.dart';

/// 框架配置
class FrameworkConfig {
  const FrameworkConfig({
    this.deviceAlias = 'Flutter Device',
    this.deviceId, // null 表示自动生成
    this.port = 53317,
    this.broadcastInterval = const Duration(seconds: 3),
    this.deviceTimeout = const Duration(seconds: 15),
    this.cleanupInterval = const Duration(seconds: 10),
    this.httpServerEnabled = true,
    this.udpListenerEnabled = true,
    this.udpBroadcastEnabled = true,
    this.relayHost,
    this.relayPort = 53317,
  });

  final String deviceAlias;
  final String? deviceId;
  final int port;
  final Duration broadcastInterval;
  final Duration deviceTimeout;
  final Duration cleanupInterval;
  final bool httpServerEnabled;
  final bool udpListenerEnabled;
  final bool udpBroadcastEnabled;
  final String? relayHost;
  final int relayPort;

  /// 转换为 TransportConfig
  TransportConfig toTransportConfig() {
    return TransportConfig(
      httpPort: port,
      enableHttp: httpServerEnabled,
      enableUdp: udpListenerEnabled || udpBroadcastEnabled,
    );
  }

  FrameworkConfig copyWith({
    String? deviceAlias,
    int? port,
    Duration? broadcastInterval,
    Duration? deviceTimeout,
    Duration? cleanupInterval,
    bool? httpServerEnabled,
    bool? udpListenerEnabled,
    bool? udpBroadcastEnabled,
    String? relayHost,
    int? relayPort,
  }) {
    return FrameworkConfig(
      deviceAlias: deviceAlias ?? this.deviceAlias,
      deviceId: deviceId ?? this.deviceId,
      port: port ?? this.port,
      broadcastInterval: broadcastInterval ?? this.broadcastInterval,
      deviceTimeout: deviceTimeout ?? this.deviceTimeout,
      cleanupInterval: cleanupInterval ?? this.cleanupInterval,
      httpServerEnabled: httpServerEnabled ?? this.httpServerEnabled,
      udpListenerEnabled: udpListenerEnabled ?? this.udpListenerEnabled,
      udpBroadcastEnabled: udpBroadcastEnabled ?? this.udpBroadcastEnabled,
      relayHost: relayHost ?? this.relayHost,
      relayPort: relayPort ?? this.relayPort,
    );
  }
}
