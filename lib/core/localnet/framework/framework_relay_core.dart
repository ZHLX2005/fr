import 'dart:async';

import 'package:http/http.dart' as http;

import '../channel/channel_manager.dart';
import '../device/device.dart';
import '../device/device_manager.dart';
import '../discovery/relay_discovery.dart';
import '../event_bus/event_bus.dart';
import '../session/session_manager.dart';
import '../transport/http_transport.dart';
import '../transport/transport_config.dart';
import '../transport/ws_transport.dart';
import '../transport_channel/relay_channel.dart';
import 'framework_config.dart';

/// Relay 后端的 FrameworkCore — 通过房间号发现 + HTTP 控制 + WS 传输
///
/// 与 FrameworkLanCore 对外暴露相同接口（deviceManager / channelManager /
/// sessionManager / eventBus），LanFramework 门面按 transportKind 分发。
class FrameworkRelayCore {
  FrameworkRelayCore({
    required this.config,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final FrameworkConfig config;
  final http.Client _httpClient;

  final EventBus eventBus = EventBus();

  late final RelayDiscovery discovery;
  late final DeviceManager deviceManager;
  late final ChannelManager channelManager;
  late final SessionManager sessionManager;

  WsTransport? _ws;
  RelayChannel? _channel;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// 启动：仅初始化 Discovery 和 managers（不连 WS）
  /// 真正的 WS 连接在调用 createAndConnect / joinAndConnect 后才建立
  Future<void> start() async {
    if (_isRunning) return;
    discovery = RelayDiscovery(
      relayUrl: config.relayUrl!,
      relayHttpPath: config.relayHttpPath,
      myDeviceId: config.deviceId ?? 'unknown',
      myAlias: config.deviceAlias,
      httpClient: _httpClient,
    );
    await discovery.start();

    deviceManager = DeviceManager(
      eventBus: eventBus,
      myDeviceId: config.deviceId ?? 'unknown',
      myAlias: config.deviceAlias,
    );
    deviceManager.attachDiscovery(discovery);

    channelManager = ChannelManager(
      eventBus: eventBus,
      deviceManager: deviceManager,
      transport: _StubHttpTransport(),
    );
    await channelManager.start();

    sessionManager = SessionManager(
      channelManager: channelManager,
      eventBus: eventBus,
    );

    _isRunning = true;
  }

  /// 创建房间 + 打开 WS 连接（注意：会尝试真实 WS 连接，请仅在集成测试时调用）
  Future<String> createAndConnect() async {
    final info = await discovery.createRoom();
    _ws = await _openWs(info.wsUrl);
    _channel = RelayChannel(ws: _ws!, myDeviceId: config.deviceId ?? 'unknown');
    return info.roomCode;
  }

  /// 加入房间 + 打开 WS 连接
  Future<void> joinAndConnect({required String roomCode}) async {
    final peer = await discovery.joinRoom(roomCode: roomCode);
    final wsUrl =
        '${config.relayUrl!.replaceFirst('http', 'ws')}${config.relayWsPath}?room=$roomCode&deviceId=${config.deviceId}';
    _ws = await _openWs(wsUrl);
    _channel = RelayChannel(ws: _ws!, myDeviceId: config.deviceId ?? 'unknown');
    deviceManager.addDevice(Device(
      deviceId: peer.deviceId,
      alias: peer.alias,
      ip: 'relay',
      port: 0,
      lastSeen: DateTime.now(),
      extras: const {},
    ));
  }

  Future<WsTransport> _openWs(String url) async {
    // 使用动态 import 避免循环依赖 + 仅在 connect 时加载
    final ioWs = await _ioConnect(url);
    return WsTransport(channel: ioWs, myDeviceId: config.deviceId ?? 'unknown');
  }

  Future<dynamic> _ioConnect(String url) async {
    // 简单的 ws 连接 — 实际实现可以用 IOWebSocketChannel.connect
    // 但本 task 仅做骨架；测试不会真正调用此方法
    throw UnsupportedError('_ioConnect not implemented in skeleton — Task 13+ will complete');
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    await _channel?.close();
    await _ws?.close();
    await discovery.stop();
    await channelManager.stop();
    await deviceManager.dispose();
    eventBus.dispose();
    _httpClient.close();
    _isRunning = false;
  }

  Future<void> dispose() async {
    await stop();
  }
}

/// Relay 模式专属 HttpTransport 桩 — 仅用于满足 ChannelManager 构造要求，
/// 实际消息收发应走 RelayChannel（WS），不会真的调用 HTTP handler。
class _StubHttpTransport extends HttpTransport {
  _StubHttpTransport() : super(config: const TransportConfig());

  @override
  bool get isRunning => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  // ChannelManager.start() 会无条件注册 /channel handler，
  // 这里静默接受即可（Relay 模式下不会真用 HTTP 收发）。
  @override
  void registerHandler(String path, HttpHandler handler) {}

  @override
  void unregisterHandler(String path) {}
}