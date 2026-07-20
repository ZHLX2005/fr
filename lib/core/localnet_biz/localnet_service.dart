import 'dart:async';

import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'models/localnet_config.dart';
import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/config_service.dart';
import 'services/debug_log_service.dart';
import 'services/device_id_service.dart';

/// LocalNet 服务适配层 — 基于 [LanFramework] 的薄封装
///
/// 所有操作最终委托给 LanFramework，不自行管理 WS/RelayDiscovery 生命周期。
/// 仅处理 UI 相关的消息存储 (messagesByPeer)、消息模型转换。
class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  final ConfigService config = configService;

  fw.LanFramework get _fw => fw.LanFramework.instance;

  // ============ 状态 ============

  String get deviceAlias => _fw.myAlias;
  String get deviceId => _fw.myDeviceId;
  String? get myIp => _fw.myIp;

  /// 服务状态（委托到 config service，向后兼容）
  String get serviceState => config.serviceState;

  bool get isReady => _fw.status == fw.FrameworkStatus.running;

  /// Relay 模式：当前房间号
  String? get currentRoomCode => _fw.currentRoomCode;

  // ============ 设备列表 ============

  List<LocalnetDevice> get devices =>
      _fw.devices.map(_toLocalnetDevice).toList();

  final _devicesController =
      StreamController<List<LocalnetDevice>>.broadcast();
  Stream<List<LocalnetDevice>> get devicesStream => _devicesController.stream;

  // ============ 消息列表（按 bucket id 分桶） ============

  final Map<String, List<LocalnetMessage>> _messagesByPeer = {};
  final _messagesController =
      StreamController<List<LocalnetMessage>>.broadcast();

  /// 旧版全量消息流
  Stream<List<LocalnetMessage>> get messagesStream =>
      _messagesController.stream;

  List<LocalnetMessage> get messages =>
      _messagesByPeer.values.expand((e) => e).toList();

  /// 订阅某 peer 的消息流
  Stream<List<LocalnetMessage>> watchMessages(String peerId) async* {
    yield _snapshot(peerId);
    yield* _messagesController.stream
        .where((_) => _lastPeer == peerId)
        .map((_) => _snapshot(peerId));
  }

  List<LocalnetMessage> messagesOf(String peerId) => _snapshot(peerId);

  List<LocalnetMessage> _snapshot(String peerId) =>
      List.unmodifiable(_messagesByPeer[peerId] ?? const []);

  String? _lastPeer;

  void _appendMessage(String bucketId, LocalnetMessage msg) {
    _messagesByPeer.putIfAbsent(bucketId, () => []).add(msg);
    _lastPeer = bucketId;
    _messagesController.add(_snapshot(bucketId));
  }

  // ============ 生命周期 ============

  Future<void> init() async {
    await config.init();
  }

  Future<void> start() async {
    if (isReady) return;
    if (_fw.status == fw.FrameworkStatus.init) {
      await init();
    }

    final cfg = config.config;
    final persistedDeviceId = await DeviceIdService.load();
    final fwCfg = cfg.toFrameworkConfig().copyWith(
      deviceAlias: cfg.deviceAlias,
      deviceId: persistedDeviceId,
      port: cfg.port,
    );

    await _fw.start(fwCfg);

    // 探测本机 IP
    final myIp = await fw.NetworkUtil.detectLocalIp();
    if (myIp != null) _fw.setMyIp(myIp);

    // 订阅
    _subscribe();
  }

  Future<void> stop() async {
    _unsubscribe();
    // Relay 模式下自动关闭 WS
    await _fw.stop();
  }

  void dispose() {
    stop();
    _devicesController.close();
    _messagesController.close();
  }

  // ============ 业务方法 ============

  /// 创建中继房间（仅 Relay 模式）
  Future<String> createRelayRoom() async {
    final code = await _fw.createChatRoom();
    // 设置共享桶 id，让 Host 能进聊天页
    return code;
  }

  /// 加入中继房间（仅 Relay 模式）
  Future<void> joinRelayRoom(String roomCode) async {
    await _fw.joinChatRoom(roomCode);
  }

  /// 离开房间
  Future<void> leaveRelayRoom() async {
    await _fw.leaveChatRoom();
  }

  /// 发送消息 — LAN 走 sendTo，Relay 走 WS chat
  Future<bool> sendMessage(LocalnetDevice target, String content) async {
    if (config.config.mode == MessageNetMode.relay) {
      return sendRelayMessage(content);
    }
    final result = await _fw.sendTo(target.id, 'chat', {'text': content});
    if (result.success) {
      _appendMessage(
        target.id,
        LocalnetMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderId: _fw.myDeviceId,
          senderAlias: _fw.myAlias,
          content: content,
          timestamp: DateTime.now(),
        ),
      );
      return true;
    }
    return false;
  }

  /// Relay 模式发送 chat 消息
  Future<bool> sendRelayMessage(String content) async {
    try {
      await _fw.sendChat(content, alias: _fw.myAlias);
      // 本地 echo — 写入共享桶
      final bucketId = 'relay:${_fw.currentRoomCode ?? ''}';
      _appendMessage(
        bucketId,
        LocalnetMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderId: _fw.myDeviceId,
          senderAlias: _fw.myAlias,
          content: content,
          timestamp: DateTime.now(),
        ),
      );
      return true;
    } catch (e) {
      debugLog.e('Localnet', 'relay send failed: $e');
      return false;
    }
  }

  /// 当前聊天的桶 id（Relay 模式用 `relay:roomCode`，LAN 模式用 target deviceId）
  String get relayBucketId =>
      'relay:${_fw.currentRoomCode ?? ''}';

  // ============ 配置 ============

  Future<void> updateConfig(LocalnetConfig newConfig) async {
    final oldAlias = config.config.deviceAlias;
    await config.updateConfig(newConfig);
    await _fw.updateConfig(
      newConfig.toFrameworkConfig().copyWith(
        deviceAlias: newConfig.deviceAlias,
        deviceId: deviceId,
        port: newConfig.port,
      ),
    );
    debugLog.i('Localnet', '配置已更新: $oldAlias → ${newConfig.deviceAlias}');
  }

  // ============ 内部 ============

  StreamSubscription? _devicesSub;
  StreamSubscription? _relayChatSub;
  StreamSubscription? _lanChatSub;
  bool _subscribed = false;

  void _subscribe() {
    if (_subscribed) return;
    _subscribed = true;

    _devicesSub = _fw.watchDevices().listen((devices) {
      _devicesController.add(devices.map(_toLocalnetDevice).toList());
    });

    if (config.config.mode == MessageNetMode.lan) {
      _lanChatSub = _fw.watchChannel('chat').listen(_onLanChatMessage);
    } else {
      _relayChatSub = _fw.watchChatFrames().listen(_onRelayChatFrame);
    }
  }

  void _unsubscribe() {
    _devicesSub?.cancel();
    _devicesSub = null;
    _lanChatSub?.cancel();
    _lanChatSub = null;
    _relayChatSub?.cancel();
    _relayChatSub = null;
    _subscribed = false;
  }

  void _onLanChatMessage(fw.TransportMessage msg) {
    final peer = _fw.devices.cast<fw.Device?>().firstWhere(
          (d) => d?.deviceId == msg.sourceDeviceId,
          orElse: () => null,
        );
    final alias = peer?.alias ?? msg.sourceDeviceId;
    _appendMessage(
      msg.sourceDeviceId,
      LocalnetMessage(
        id: msg.timestamp.millisecondsSinceEpoch.toString(),
        senderId: msg.sourceDeviceId,
        senderAlias: alias,
        content: msg.payload['text'] as String? ?? '',
        timestamp: msg.timestamp,
      ),
    );
  }

  void _onRelayChatFrame(fw.TransportFrame frame) {
    final chatPayload = fw.ChatPayload.fromBytes(frame.payload);
    final senderId = frame.sourceDeviceId;
    final alias = chatPayload.alias ?? senderId;
    final bucketId = relayBucketId;

    _appendMessage(
      bucketId,
      LocalnetMessage(
        id: frame.timestamp.millisecondsSinceEpoch.toString(),
        senderId: senderId,
        senderAlias: alias,
        content: chatPayload.text,
        timestamp: frame.timestamp,
      ),
    );
  }

  LocalnetDevice _toLocalnetDevice(fw.Device d) {
    return LocalnetDevice(
      id: d.deviceId,
      alias: d.alias,
      ip: d.ip,
      port: d.port,
      deviceType: DeviceType.desktop,
      version: '1.0',
      lastSeen: d.lastSeen,
    );
  }
}

final localnetService = LocalnetService();
