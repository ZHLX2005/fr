import 'dart:async';

import 'package:web_socket_channel/io.dart';
import 'package:xiaodouzi_fr/api/goframe/room/room_endpoint.dart';

import '../channel/channel_manager.dart';
import '../connection/connection_manager.dart';
import '../device/device.dart';
import '../device/device_manager.dart';
import '../discovery/relay_discovery.dart';
import '../event_bus/event_bus.dart';
import '../session/session_manager.dart';
import '../transport/http_transport.dart';
import '../transport/transport_config.dart';
import '../transport/udp_transport.dart';
import '../transport/ws_transport.dart';
import '../transport_channel/relay_channel.dart';
import 'framework_config.dart';

/// Relay 后端的 FrameworkCore — 通过房间号发现 + HTTP 控制 + WS 传输
///
/// 与 FrameworkLanCore 对外暴露相同接口（deviceManager / channelManager /
/// sessionManager / eventBus），LanFramework 门面按 transportKind 分发。
///
/// 注意：sendTo / watchChannel 仅支持 LAN。Relay 模式请使用 createSession，
/// 由 SessionManager 管理状态同步。
class FrameworkRelayCore {
  FrameworkRelayCore({required this.config, RoomEndpoint? roomEndpoint})
    : _roomEndpoint = roomEndpoint ?? RoomEndpoint(
         baseUrl: config.relayUrl ?? 'http://localhost',
         pathPrefix: config.relayHttpPath,
       );

  final FrameworkConfig config;
  final RoomEndpoint _roomEndpoint;

  final EventBus eventBus = EventBus();

  late final RelayDiscovery discovery;
  late final DeviceManager deviceManager;
  late final UdpTransport udpTransport = _UnsupportedUdpTransport();
  late final HttpTransport httpTransport = _StubHttpTransport();
  late final ChannelManager channelManager;
  late final ConnectionManager connectionManager;
  late final SessionManager sessionManager;

  Stream<String> get multicasts => Stream<String>.empty();

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
      roomEndpoint: _roomEndpoint,
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
      transport: httpTransport,
    );
    await channelManager.start();

    connectionManager = ConnectionManager(
      eventBus: eventBus,
      deviceManager: deviceManager,
    );

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
    final joinInfo = await discovery.joinRoom(roomCode: roomCode);
    _ws = await _openWs(joinInfo.wsUrl);
    _channel = RelayChannel(ws: _ws!, myDeviceId: config.deviceId ?? 'unknown');
    deviceManager.addDevice(
      Device(
        deviceId: joinInfo.host.deviceId,
        alias: joinInfo.host.alias,
        ip: 'relay',
        port: 0,
        lastSeen: DateTime.now(),
        extras: const {},
      ),
    );
  }

  Future<WsTransport> _openWs(String url) async {
    final ioWs = IOWebSocketChannel.connect(Uri.parse(url));
    return WsTransport(channel: ioWs, myDeviceId: config.deviceId ?? 'unknown');
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    await _channel?.close();
    await _ws?.close();
    await discovery.stop();
    await connectionManager.stop();
    await channelManager.stop();
    await deviceManager.dispose();
    _isRunning = false;
  }

  Future<void> dispose() async {
    await stop();
    eventBus.dispose();
  }
}

class _UnsupportedUdpTransport extends UdpTransport {
  _UnsupportedUdpTransport() : super(config: const TransportConfig());

  @override
  void sendRaw(String payload) {
    throw UnsupportedError('UDP multicast is LAN-only.');
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
