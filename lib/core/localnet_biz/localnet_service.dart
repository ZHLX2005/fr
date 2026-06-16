import 'dart:async';
import 'dart:io';

import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'models/localnet_config.dart';
import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/config_service.dart';
import 'services/debug_log_service.dart';
import 'services/device_id_service.dart';

/// LocalNet 服务适配层 — 基于 [LanFramework] 的薄封装
///
/// 保持与旧业务代码兼容的公开 API，内部全部委托给 LanFramework。
/// 新代码请直接使用 `LanFramework.instance`。
@Deprecated('Use LanFramework.instance instead')
class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  final ConfigService config = configService;

  // ============ 框架引用 ============

  fw.LanFramework get _fw => fw.LanFramework.instance;

  // ============ 状态常量（兼容旧代码） ============

  static const String stateInit = 'INIT';
  static const String stateIdle = 'IDLE';
  static const String stateStarting = 'STARTING';
  static const String stateRunning = 'RUNNING';
  static const String stateStopping = 'STOPPING';
  static const String stateError = 'ERROR';

  String _serviceState = stateInit;
  String get serviceState => _serviceState;

  String get deviceAlias => _fw.myAlias;
  String get deviceId => _fw.myDeviceId;
  String? get myIp => _fw.myIp;

  bool get isInitialized => _fw.status != fw.FrameworkStatus.init;
  bool get isUdpBroadcastRunning => _fw.status == fw.FrameworkStatus.running;
  bool get isUdpListenerRunning => _fw.status == fw.FrameworkStatus.running;
  bool get isHttpServerRunning => _fw.status == fw.FrameworkStatus.running;

  // ============ 设备列表（兼容旧 LocalnetDevice 模型） ============

  List<LocalnetDevice> get devices =>
      _fw.devices.map(_toLocalnetDevice).toList();

  final _devicesController =
      StreamController<List<LocalnetDevice>>.broadcast();
  Stream<List<LocalnetDevice>> get devicesStream => _devicesController.stream;

  // ============ 消息列表（按 peerId 分桶） ============
  //
  // 旧实现是全局 _messages，所有 peer 共享一份，聊天页之间串台。
  // 现在按 (peerId, list) 桶，聊天页只订阅自己跟当前 peer 的桶。
  final Map<String, List<LocalnetMessage>> _messagesByPeer = {};
  final _messagesController =
      StreamController<List<LocalnetMessage>>.broadcast();

  /// 当前 peer 的消息快照（向后兼容，等同于第一个 peer 的桶）
  List<LocalnetMessage> get messages =>
      _messagesByPeer.values.expand((e) => e).toList();

  /// 旧版全量消息流（保留兼容，首版会全量合并所有桶；新代码用 [watchMessages]）
  Stream<List<LocalnetMessage>> get messagesStream =>
      _messagesController.stream;

  /// 订阅某 peer 的消息流（推荐用法）
  Stream<List<LocalnetMessage>> watchMessages(String peerId) async* {
    yield _snapshot(peerId);
    yield* _messagesController.stream
        .where((_) => _lastPeer == peerId)
        .map((_) => _snapshot(peerId));
  }

  /// 取某 peer 的消息快照
  List<LocalnetMessage> messagesOf(String peerId) => _snapshot(peerId);

  List<LocalnetMessage> _snapshot(String peerId) =>
      List.unmodifiable(_messagesByPeer[peerId] ?? const []);

  /// 临时记录最近一次消息触达的 peer（用于在流过滤器里窄化）
  String? _lastPeer;

  void _appendMessage(String peerId, LocalnetMessage msg) {
    _messagesByPeer.putIfAbsent(peerId, () => []).add(msg);
    _lastPeer = peerId;
    _messagesController.add(_snapshot(peerId));
  }

  StreamSubscription? _devicesSub;
  StreamSubscription? _channelSub;
  bool _subscribed = false;

  // ============ 生命周期 ============

  Future<void> init() async {
    if (_serviceState != stateInit) return;
    _logState(_serviceState, stateStarting, note: '初始化');

    await config.init();
    _serviceState = stateIdle;
    _logState(stateStarting, stateIdle, note: '初始化完成');
  }

  Future<void> start() async {
    if (_serviceState == stateRunning || _serviceState == stateStarting) return;

    if (!isInitialized) await init();
    _serviceState = stateStarting;

    try {
      await applyConfig();

      final cfg = config.config;
      // 优先用持久化的 deviceId（首次启动会生成并落盘），
      // 避免每次启动换 UUID 导致对端看到"老 B 离线 + 新 B 上线"两条记录。
      final persistedDeviceId = await DeviceIdService.load();
      final fwCfg = fw.FrameworkConfig(
        deviceAlias: cfg.deviceAlias,
        deviceId: persistedDeviceId,
        port: cfg.port,
        udpBroadcastEnabled: cfg.udpBroadcastEnabled,
        udpListenerEnabled: cfg.udpListenerEnabled,
        httpServerEnabled: cfg.httpServerEnabled,
      );

      await _fw.start(fwCfg);

      // 探测本机 IP
      final myIp = await _detectLocalIp();
      if (myIp != null) _fw.setMyIp(myIp);

      // 模拟器中继
      if (myIp != null && myIp.startsWith('10.0.2.')) {
        // LanFramework 当前不支持运行时修改 relay host
        debugLog.i('Localnet', '模拟器环境检测到，请手动配置中继');
      }

      // 订阅设备变化和通道消息
      _subscribe();

      _serviceState = stateRunning;
      _logState(stateStarting, stateRunning, note: '服务已启动');
    } catch (e) {
      _serviceState = stateError;
      debugLog.e('Localnet', '启动失败: $e');
      _logState(stateStarting, stateError, note: '启动失败: $e');
    }
  }

  Future<void> applyConfig() async {
    final cfg = config.config;
    debugLog.i('Localnet', '配置已应用: ${cfg.deviceAlias} :${cfg.port}');
  }

  Future<void> stop() async {
    final from = _serviceState;
    if (_serviceState != stateRunning && _serviceState != stateStarting) return;

    _serviceState = stateStopping;
    _unsubscribe();
    await _fw.stop();
    _serviceState = stateIdle;
    _logState(from, stateIdle, note: '服务已停止');
  }

  void dispose() {
    stop();
    _devicesController.close();
    _messagesController.close();
  }

  // ============ 业务方法 ============

  Future<bool> sendMessage(LocalnetDevice target, String content) async {
    final result = await _fw.sendTo(target.id, 'chat', {'text': content});
    if (result.success) {
      // 按 target 设备 id 分桶，本地发出的消息只入"和它的会话"那个桶
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

  Future<void> updateConfig(LocalnetConfig newConfig) async {
    final oldAlias = config.config.deviceAlias;
    await config.updateConfig(newConfig);
    await applyConfig();
    _logState(
      _serviceState,
      _serviceState,
      note: '配置已更新: $oldAlias → ${newConfig.deviceAlias}',
    );

    if (_serviceState == stateRunning) {
      debugLog.i('Localnet', '配置已更改，重启服务...');
      await stop();
      await start();
    }
  }

  // ============ 组件独立控制（兼容桩） ============

  Future<void> startUdpBroadcast() async {
    await _fw.start(config.config.toFrameworkConfig());
  }

  void stopUdpBroadcast() => _fw.stop();

  Future<void> startUdpListener() async {
    if (_fw.status != fw.FrameworkStatus.running) {
      await _fw.start(config.config.toFrameworkConfig());
    }
  }

  void stopUdpListener() => _fw.stop();

  Future<void> startHttpServer() async {
    if (_fw.status != fw.FrameworkStatus.running) {
      await _fw.start(config.config.toFrameworkConfig());
    }
  }

  void stopHttpServer() => _fw.stop();

  // ============ 内部辅助 ============

  void _logState(String from, String to, {String? note}) {
    debugLog.logState('Localnet', from, to, note: note);
  }

  void _subscribe() {
    if (_subscribed) return;
    _subscribed = true;

    _devicesSub = _fw.watchDevices().listen((devices) {
      _devicesController.add(devices.map(_toLocalnetDevice).toList());
    });

    _channelSub = _fw.watchChannel('chat').listen((msg) {
      // 别名以"发送方 deviceId 在我本地 deviceRegistry 里查到的最新记录"为准。
      // 不取 msg.payload['alias']——payload 是纯数据载荷，不该承担身份字段。
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
    });
  }

  void _unsubscribe() {
    _devicesSub?.cancel();
    _devicesSub = null;
    _channelSub?.cancel();
    _channelSub = null;
    _subscribed = false;
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

  /// 探测本机 IPv4（路由可达的接口 IP）
  ///
  /// Android 上 `NetworkInterface.list` 经常只返回 `lo` 或空集，
  /// 因此用 `InternetAddress.lookup` 解析一个外网域名，由系统选路填充
  /// 真实活跃接口 IP；空集合时回退到枚举网络接口。
  Future<String?> _detectLocalIp() async {
    // 1) DNS 反查：让系统帮我们挑活跃接口
    try {
      final addrs = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 2));
      for (final addr in addrs) {
        final ip = addr.address;
        if (ip.isNotEmpty && ip != '0.0.0.0') return ip;
      }
    } catch (_) {}

    // 2) 回退：枚举网络接口
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.isEmpty || ip == '0.0.0.0') continue;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }
    } catch (_) {}

    return null;
  }
}

final localnetService = LocalnetService();
