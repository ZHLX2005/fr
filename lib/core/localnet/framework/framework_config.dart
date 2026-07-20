import '../transport/transport_config.dart';
import '../transport/transport_kind.dart';

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
    this.transportKind = TransportKind.lan,
    this.relayUrl,
    this.relayHttpPath = '/api/v1',
    this.relayWsPath = '/ws',
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
  final TransportKind transportKind;
  final String? relayUrl;
  final String relayHttpPath;
  final String relayWsPath;

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
    String? deviceId,
    int? port,
    Duration? broadcastInterval,
    Duration? deviceTimeout,
    Duration? cleanupInterval,
    bool? httpServerEnabled,
    bool? udpListenerEnabled,
    bool? udpBroadcastEnabled,
    TransportKind? transportKind,
    String? relayUrl,
    String? relayHttpPath,
    String? relayWsPath,
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
      transportKind: transportKind ?? this.transportKind,
      relayUrl: relayUrl ?? this.relayUrl,
      relayHttpPath: relayHttpPath ?? this.relayHttpPath,
      relayWsPath: relayWsPath ?? this.relayWsPath,
    );
  }
}
