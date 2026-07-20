import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';

import 'localnet_constants.dart';

/// MessageNet 业务模式 — 决定走 LAN 后端还是 Relay 后端
enum MessageNetMode {
  /// 局域网：UDP 多播发现 + HTTP P2P 消息（同 WiFi / 同子网）
  lan,

  /// 互联网：HTTP 控制面（房间号）+ WS 多路复用消息（跨网络，需中继服务器）
  relay,
}

class LocalnetConfig {
  static const String _keyDeviceAlias = 'localnet_device_alias';
  static const String _keyHttpEnabled = 'localnet_http_enabled';
  static const String _keyMulticastEnabled = 'localnet_multicast_enabled';
  static const String _keyUdpBroadcastEnabled =
      'localnet_udp_broadcast_enabled';
  static const String _keyUdpListenerEnabled = 'localnet_udp_listener_enabled';
  static const String _keyHttpServerEnabled = 'localnet_http_server_enabled';
  static const String _keyPort = 'localnet_port';
  static const String _keyMode = 'message_net_mode';
  static const String _keyRelayUrl = 'message_net_relay_url';

  /// 默认中继服务器（生产环境，已通过 BACKEND_GUIDE 契约 6/6 + WS roundtrip 验证）
  static const String defaultRelayUrl = 'http://47.110.80.47:8988';

  final String deviceAlias;
  final bool httpEnabled;
  final bool multicastEnabled;
  final bool udpBroadcastEnabled;
  final bool udpListenerEnabled;
  final bool httpServerEnabled;
  final int port;

  /// 消息通讯模式（LAN / Relay）
  final MessageNetMode mode;

  /// Relay 模式下使用的中继服务器 URL（仅 mode == relay 时生效）
  final String relayUrl;

  const LocalnetConfig({
    this.deviceAlias = LocalnetConstants.defaultDeviceAlias,
    this.httpEnabled = true,
    this.multicastEnabled = true,
    this.udpBroadcastEnabled = true,
    this.udpListenerEnabled = true,
    this.httpServerEnabled = true,
    this.port = LocalnetConstants.defaultPort,
    this.mode = MessageNetMode.lan,
    this.relayUrl = defaultRelayUrl,
  });

  LocalnetConfig copyWith({
    String? deviceAlias,
    bool? httpEnabled,
    bool? multicastEnabled,
    bool? udpBroadcastEnabled,
    bool? udpListenerEnabled,
    bool? httpServerEnabled,
    int? port,
    MessageNetMode? mode,
    String? relayUrl,
  }) {
    return LocalnetConfig(
      deviceAlias: deviceAlias ?? this.deviceAlias,
      httpEnabled: httpEnabled ?? this.httpEnabled,
      multicastEnabled: multicastEnabled ?? this.multicastEnabled,
      udpBroadcastEnabled: udpBroadcastEnabled ?? this.udpBroadcastEnabled,
      udpListenerEnabled: udpListenerEnabled ?? this.udpListenerEnabled,
      httpServerEnabled: httpServerEnabled ?? this.httpServerEnabled,
      port: port ?? this.port,
      mode: mode ?? this.mode,
      relayUrl: relayUrl ?? this.relayUrl,
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
    'mode': mode.name,
    'relayUrl': relayUrl,
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
      mode: MessageNetMode.values.firstWhere(
        (e) => e.name == (json['mode'] as String?),
        orElse: () => MessageNetMode.lan,
      ),
      relayUrl: json['relayUrl'] as String? ?? defaultRelayUrl,
    );
  }

  static Future<LocalnetConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final config = LocalnetConfig(
      deviceAlias:
          prefs.getString(_keyDeviceAlias) ??
          LocalnetConstants.defaultDeviceAlias,
      httpEnabled: prefs.getBool(_keyHttpEnabled) ?? true,
      multicastEnabled: prefs.getBool(_keyMulticastEnabled) ?? true,
      udpBroadcastEnabled: prefs.getBool(_keyUdpBroadcastEnabled) ?? true,
      udpListenerEnabled: prefs.getBool(_keyUdpListenerEnabled) ?? true,
      httpServerEnabled: prefs.getBool(_keyHttpServerEnabled) ?? true,
      port: prefs.getInt(_keyPort) ?? LocalnetConstants.defaultPort,
      mode: MessageNetMode.values.firstWhere(
        (e) => e.name == prefs.getString(_keyMode),
        orElse: () => MessageNetMode.lan,
      ),
      relayUrl: prefs.getString(_keyRelayUrl) ?? defaultRelayUrl,
    );
    // 守卫：若三项开关全被持久化为 false（历史脏数据 / 误操作），
    // 视为无效配置，回退默认（至少开启 HTTP，否则框架无法工作）。
    if (!config.udpBroadcastEnabled &&
        !config.udpListenerEnabled &&
        !config.httpServerEnabled) {
      return const LocalnetConfig();
    }
    return config;
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
    await prefs.setString(_keyMode, mode.name);
    await prefs.setString(_keyRelayUrl, relayUrl);
  }

  @override
  String toString() =>
      'LocalnetConfig(alias: $deviceAlias, http: $httpEnabled, multicast: $multicastEnabled, '
      'udpBroadcast: $udpBroadcastEnabled, udpListener: $udpListenerEnabled, '
      'httpServer: $httpServerEnabled, port: $port, mode: $mode, relayUrl: $relayUrl)';

  /// 转换为 FrameworkConfig（新框架）
  ///
  /// LAN 模式：transportKind = lan，使用 udp/http 开关
  /// Relay 模式：transportKind = relay，使用 relayUrl
  FrameworkConfig toFrameworkConfig() {
    if (mode == MessageNetMode.relay) {
      return FrameworkConfig(
        deviceAlias: deviceAlias,
        port: port,
        transportKind: TransportKind.relay,
        relayUrl: relayUrl,
        // Relay 模式下 udp/http 开关不起作用（由 FrameworkRelayCore 内部决定）
        httpServerEnabled: false,
        udpListenerEnabled: false,
        udpBroadcastEnabled: false,
      );
    }
    return FrameworkConfig(
      deviceAlias: deviceAlias,
      port: port,
      transportKind: TransportKind.lan,
      httpServerEnabled: httpServerEnabled,
      udpListenerEnabled: udpListenerEnabled,
      udpBroadcastEnabled: udpBroadcastEnabled,
    );
  }
}
