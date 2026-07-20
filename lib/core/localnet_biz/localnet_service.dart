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
/// # 设计原则
///
/// **对 LAN / Relay 模式完全无感知。** 所有底层通信统一委托给 [TransportService]：
///
/// | 操作 | 引擎接口 |
/// |------|---------|
/// | 发送消息 | `fw.sendTo(targetId, 'chat', {'text': ..., 'alias': ...})` |
/// | 接收消息 | `fw.watchChannel('chat')` → `TransportMessage{payload: {text, alias}}` |
///
/// 引擎保证 LAN（HTTP P2P）和 Relay（WS 帧）走同一套 wire format，
/// biz 层不需要知道对端是通过同子网还是中继服务器连接。
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

  /// 发送消息 — 统一接口，LAN/Relay 均走 [TransportService]
  Future<bool> sendMessage(String targetId, String content) async {
    final result = await _fw.sendTo(targetId, 'chat', {
      'text': content,
      'alias': _fw.myAlias,
    });
    if (result.success) {
      _echoLocal(targetId, content);
      return true;
    }
    return false;
  }

  /// 本地 echo（写入自己发送的消息，不要等服务器返回）
  void _echoLocal(String bucketId, String content) {
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
  StreamSubscription? _chatSub;
  bool _subscribed = false;

  void _subscribe() {
    if (_subscribed) return;
    _subscribed = true;

    _devicesSub = _fw.watchDevices().listen((devices) {
      _devicesController.add(devices.map(_toLocalnetDevice).toList());
    });

    // 统一订阅 chat 通道 — LAN / Relay 引擎保证同一 wire format
    _chatSub = _fw.watchChannel('chat').listen(_onChatMessage);
  }

  void _unsubscribe() {
    _devicesSub?.cancel();
    _devicesSub = null;
    _chatSub?.cancel();
    _chatSub = null;
    _subscribed = false;
  }

  void _onChatMessage(fw.TransportMessage msg) {
    final text = msg.payload['text'] as String? ?? '';
    final alias = msg.payload['alias'] as String? ?? msg.sourceDeviceId;
    final bucketId = msg.sourceDeviceId;

    _appendMessage(
      bucketId,
      LocalnetMessage(
        id: msg.timestamp.millisecondsSinceEpoch.toString(),
        senderId: msg.sourceDeviceId,
        senderAlias: alias,
        content: text,
        timestamp: msg.timestamp,
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
