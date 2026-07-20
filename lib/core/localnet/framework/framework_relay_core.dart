import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';
import 'package:xiaodouzi_fr/api/goframe/room/room_endpoint.dart';

import '../channel/channel_manager.dart';
import '../connection/connection_manager.dart';
import '../device/device.dart';
import '../device/device_manager.dart';
import '../discovery/relay_discovery.dart';
import '../event_bus/event_bus.dart';
import '../session/session_manager.dart';
import '../transport/chat_payload.dart';
import '../transport/http_transport.dart';
import '../transport/transport_config.dart';
import '../transport/transport_frame.dart';
import '../transport/udp_transport.dart';
import '../transport/ws_transport.dart';
import '../transport_channel/relay_channel.dart';
import 'framework_config.dart';

/// Relay 后端的 FrameworkCore — 通过房间号发现 + HTTP 控制 + WS 传输
///
/// 与 FrameworkLanCore 对外暴露相同接口（deviceManager / channelManager /
/// sessionManager / eventBus），LanFramework 门面按 transportKind 分发。
///
/// 注意：sendTo / watchChannel 仅支持 LAN。Relay 模式请使用本类提供的
/// createChatRoom / joinChatRoom / sendChat / watchChat 等 API。
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

  /// 当前房间号（有 WS 连接时可用）
  String? _currentRoomCode;
  String? get currentRoomCode => _currentRoomCode;

  /// WS 聊天帧流（subscribe 后可用）
  final StreamController<TransportFrame> _chatCtrl =
      StreamController<TransportFrame>.broadcast();
  StreamSubscription<TransportFrame>? _chatSub;

  /// 订阅 chat channel 的入站帧
  Stream<TransportFrame> get chatFrames => _chatCtrl.stream;

  // ============ 生命周期 ============

  /// 启动：仅初始化 Discovery 和 managers（不连 WS）
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

  /// 创建房间 + WS 连接 + identify + 启动聊天流
  ///
  /// 返回 (roomCode, wsUrl)，调用方保存 roomCode 做后续标识。
  Future<String> createChatRoom() async {
    _assertReady();
    final info = await discovery.createRoom();
    _currentRoomCode = info.roomCode;
    await _connectAndIdentify(info.wsUrl, role: 'host');
    return info.roomCode;
  }

  /// 加入房间 + WS 连接 + identify + 启动聊天流
  ///
  /// 成功时返回 wsUrl；调用方可读取 [currentRoomCode]。
  Future<String> joinChatRoom(String roomCode) async {
    _assertReady();
    final result = await discovery.joinRoom(roomCode: roomCode);
    _currentRoomCode = roomCode;
    await _connectAndIdentify(result.wsUrl, role: 'guest');

    // 将 host 添加为设备
    deviceManager.addDevice(
      Device(
        deviceId: result.host.deviceId,
        alias: result.host.alias,
        ip: 'relay',
        port: 0,
        lastSeen: DateTime.now(),
        extras: const {},
      ),
    );
    return result.wsUrl;
  }

  /// 发送 chat 消息（自动编码为 ChatPayload）
  Future<void> sendChat(String text, {String? alias}) async {
    _assertConnected();
    final payload = ChatPayload(text: text, alias: alias).toBytes();
    await _channel!.send('chat', payload);
  }

  /// 离开房间 — 关闭 WS + 清理订阅
  Future<void> leaveChatRoom() async {
    await _chatSub?.cancel();
    _chatSub = null;
    await _channel?.close();
    _channel = null;
    await _ws?.close();
    _ws = null;
    _currentRoomCode = null;
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

  /// 完整 WS 连接流程：open → WsTransport → RelayChannel → subscribe → identify
  Future<void> _connectAndIdentify(String wsUrl, {required String role}) async {
    // 先清理旧连接
    await leaveChatRoom();

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

    // 订阅 chat 帧到公开流
    _chatSub = _channel!.watch('chat').listen(
      (frame) => _chatCtrl.add(frame),
      onError: (e) => _chatCtrl.addError(e),
    );

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
    final info = await discovery.createRoom();
    final ioWs = IOWebSocketChannel.connect(Uri.parse(info.wsUrl));
    _ws = WsTransport(channel: ioWs, myDeviceId: config.deviceId ?? 'unknown');
    _channel = RelayChannel(ws: _ws!, myDeviceId: config.deviceId ?? 'unknown');
    return info.roomCode;
  }

  /// 加入房间 + 打开 WS 连接（兼容旧 API）
  Future<void> joinAndConnect({required String roomCode}) async {
    final joinInfo = await discovery.joinRoom(roomCode: roomCode);
    final ioWs = IOWebSocketChannel.connect(Uri.parse(joinInfo.wsUrl));
    _ws = WsTransport(channel: ioWs, myDeviceId: config.deviceId ?? 'unknown');
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

  Future<void> stop() async {
    if (!_isRunning) return;
    await leaveChatRoom();
    await discovery.stop();
    await connectionManager.stop();
    await channelManager.stop();
    await deviceManager.dispose();
    _roomEndpoint.dispose();
    _isRunning = false;
  }

  Future<void> dispose() async {
    await stop();
    await _chatCtrl.close();
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
