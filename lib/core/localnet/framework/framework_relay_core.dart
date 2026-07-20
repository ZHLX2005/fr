import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';
import 'package:xiaodouzi_fr/api/goframe/room/room_endpoint.dart';

import '../channel/channel_manager.dart';
import '../connection/connection_manager.dart';
import '../device/device.dart';
import '../device/device_manager.dart';
import '../discovery/discovery_event.dart';
import '../discovery/relay_discovery.dart';
import '../event_bus/event_bus.dart';
import '../session/session_manager.dart';
import '../transport/http_transport.dart';
import '../transport/transport_config.dart';
import '../transport/transport_frame.dart';
import '../transport/udp_transport.dart';
import '../transport/ws_transport.dart';
import '../transport_channel/relay_channel.dart';
import '../transport_service/relay_transport_service.dart';
import '../transport_service/transport_service.dart';
import 'framework_config.dart';
import 'framework_core.dart';

/// Relay 后端的 FrameworkCore — 通过房间号发现 + HTTP 控制 + WS 传输
///
/// 实现 [FrameworkCore] 抽象父类：
/// - [discovery]: [RelayDiscovery]（HTTP 房间 API）
/// - [transport]: [RelayTransportService]（WS 帧；通过 createChatRoom/joinChatRoom 激活）
/// - [deviceManager], [connectionManager], [sessionManager], [eventBus]
class FrameworkRelayCore implements FrameworkCore {
  FrameworkRelayCore({required this.config, RoomEndpoint? roomEndpoint})
    : _roomEndpoint = roomEndpoint ?? RoomEndpoint(
         baseUrl: config.relayUrl ?? 'http://localhost',
         pathPrefix: config.relayHttpPath,
       );

  final FrameworkConfig config;
  final RoomEndpoint _roomEndpoint;

  // ============ FrameworkCore 接口实现 ============

  @override
  final EventBus eventBus = EventBus();

  @override
  late final RelayDiscovery discovery;

  @override
  late final DeviceManager deviceManager;

  @override
  late final ConnectionManager connectionManager;

  @override
  late final SessionManager sessionManager;

  @override
  late final TransportService transport;

  // 保留旧属性兼容
  late final UdpTransport udpTransport = _UnsupportedUdpTransport();
  late final HttpTransport httpTransport = _StubHttpTransport();
  late final ChannelManager channelManager;

  Stream<String> get multicasts => Stream<String>.empty();

  WsTransport? _ws;
  RelayChannel? _channel;
  RelayTransportService? _relayTransport;
  bool _isRunning = false;

  @override
  bool get isRunning => _isRunning;

  /// 当前房间号（有 WS 连接时可用）
  String? _currentRoomCode;
  String? get currentRoomCode => _currentRoomCode;

  // ============ 生命周期 ============

  @override
  Future<void> start() async {
    if (_isRunning) return;

    // 1. 创建 RelayTransportService（起始态：disconnected）
    _relayTransport = RelayTransportService(myDeviceId: config.deviceId ?? 'unknown');
    transport = _relayTransport!;

    // 2. 初始化 Discovery
    discovery = RelayDiscovery(
      relayUrl: config.relayUrl!,
      relayHttpPath: config.relayHttpPath,
      myDeviceId: config.deviceId ?? 'unknown',
      myAlias: config.deviceAlias,
      roomEndpoint: _roomEndpoint,
    );
    await discovery.start();

    // 3. DeviceManager（挂载 discovery 事件）
    deviceManager = DeviceManager(
      eventBus: eventBus,
      myDeviceId: config.deviceId ?? 'unknown',
      myAlias: config.deviceAlias,
    );
    deviceManager.attachDiscovery(discovery);

    // 4. ChannelManager（用 stub httpTransport 满足依赖，relay 不走 HTTP P2P）
    channelManager = ChannelManager(
      eventBus: eventBus,
      deviceManager: deviceManager,
      transport: httpTransport,
    );
    await channelManager.start();

    // 5. ConnectionManager
    connectionManager = ConnectionManager(
      eventBus: eventBus,
      deviceManager: deviceManager,
    );

    // 6. SessionManager
    sessionManager = SessionManager(
      channelManager: channelManager,
      eventBus: eventBus,
    );

    _isRunning = true;
  }

  /// 创建房间 + WS 连接 + identify（激活 TransportService）
  Future<String> createChatRoom() async {
    _assertReady();
    final roomCode = await discovery.createRoom();
    if (roomCode == null) throw StateError('createRoom 返回 null');
    _currentRoomCode = roomCode;
    final wsUrl = '${config.relayUrl!.replaceFirst('http', 'ws')}/ws/$roomCode';
    await _connectAndIdentify(wsUrl, role: 'host');
    return roomCode;
  }

  /// 加入房间 + WS 连接 + identify（激活 TransportService）
  Future<String> joinChatRoom(String roomCode) async {
    _assertReady();
    final result = await discovery.joinRoom(roomCode);
    if (result == null) throw StateError('joinRoom 返回 null');
    _currentRoomCode = roomCode;
    final host = (result as RoomJoined).host;
    final wsUrl = '${config.relayUrl!.replaceFirst('http', 'ws')}/ws/$roomCode';
    await _connectAndIdentify(wsUrl, role: 'guest');

    deviceManager.addDevice(
      Device(
        deviceId: host.deviceId,
        alias: host.alias,
        ip: 'relay',
        port: 0,
        lastSeen: DateTime.now(),
        extras: const {},
      ),
    );
    return wsUrl;
  }

  /// 离开房间 — 关闭 WS + 清理
  Future<void> leaveChatRoom() async {
    await _channel?.close();
    _channel = null;
    await _ws?.close();
    _ws = null;
    _currentRoomCode = null;

    // 断开 RelayTransportService
    _relayTransport?.disconnect();
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    await leaveChatRoom();
    await discovery.stop();
    await connectionManager.stop();
    await channelManager.stop();
    await deviceManager.dispose();
    _relayTransport?.dispose();
    _roomEndpoint.dispose();
    _isRunning = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    eventBus.dispose();
  }

  // ============ 内部 ============

  void _assertReady() {
    if (!_isRunning) {
      throw StateError('FrameworkRelayCore 未 start()');
    }
  }

  void _assertConnected() {
    if (_channel == null || _ws == null) {
      throw StateError('未连接聊天室，请先调用 createChatRoom 或 joinChatRoom');
    }
  }

  /// 完整 WS 连接流程：open → WsTransport → RelayChannel → RelayTransportService → subscribe → identify
  Future<void> _connectAndIdentify(String wsUrl, {required String role}) async {
    // 先清理旧连接（仅关闭 ws/channel，不重置 _currentRoomCode）
    _channel?.close();
    _channel = null;
    _ws?.close();
    _ws = null;
    _relayTransport?.disconnect();

    final ioWs = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = WsTransport(channel: ioWs, myDeviceId: config.deviceId ?? 'unknown');
    _channel = RelayChannel(
      ws: _ws!,
      myDeviceId: config.deviceId ?? 'unknown',
    );

    // 打开 chat 通道
    await _channel!.open(
      channelName: 'chat',
      remoteDeviceId: 'relay',
    );

    // 激活 RelayTransportService（之后 biz 通过 transport.sendTo/watchChannel 通信）
    _relayTransport?.connect(_ws!, _channel!);

    // 发送 identify（服务端必须收到才能分配 slot）
    final identifyPayload = utf8.encode(jsonEncode({'role': role}));
    await _ws!.send(TransportFrame(
      channelName: 'identify',
      sourceDeviceId: config.deviceId ?? 'unknown',
      payload: Uint8List.fromList(identifyPayload),
      timestamp: DateTime.now(),
    ));
  }

  // ============ 原有方法（兼容） ============

  /// 创建房间 + 打开 WS 连接（兼容旧 API，不进聊天订阅）
  Future<String> createAndConnect() async {
    final roomCode = await discovery.createRoom();
    if (roomCode == null) throw StateError('createRoom 返回 null');
    final wsUrl = '${config.relayUrl!.replaceFirst('http', 'ws')}/ws/$roomCode';
    final ioWs = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = WsTransport(channel: ioWs, myDeviceId: config.deviceId ?? 'unknown');
    _channel = RelayChannel(ws: _ws!, myDeviceId: config.deviceId ?? 'unknown');
    return roomCode;
  }

  /// 加入房间 + 打开 WS 连接（兼容旧 API）
  Future<void> joinAndConnect({required String roomCode}) async {
    final joinInfo = await discovery.joinRoom(roomCode);
    if (joinInfo == null) throw StateError('joinRoom 返回 null');
    final host = (joinInfo as RoomJoined).host;
    final wsUrl = '${config.relayUrl!.replaceFirst('http', 'ws')}/ws/$roomCode';
    final ioWs = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = WsTransport(channel: ioWs, myDeviceId: config.deviceId ?? 'unknown');
    _channel = RelayChannel(ws: _ws!, myDeviceId: config.deviceId ?? 'unknown');
    deviceManager.addDevice(
      Device(
        deviceId: host.deviceId,
        alias: host.alias,
        ip: 'relay',
        port: 0,
        lastSeen: DateTime.now(),
        extras: const {},
      ),
    );
  }
}

class _UnsupportedUdpTransport extends UdpTransport {
  _UnsupportedUdpTransport() : super(config: const TransportConfig());

  @override
  void sendRaw(String payload) {
    throw UnsupportedError('UDP multicast is LAN-only.');
  }
}

/// Relay 模式专属 HttpTransport 桩 — 仅用于满足 ChannelManager 构造要求。
class _StubHttpTransport extends HttpTransport {
  _StubHttpTransport() : super(config: const TransportConfig());

  @override
  bool get isRunning => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void registerHandler(String path, HttpHandler handler) {}

  @override
  void unregisterHandler(String path) {}
}
