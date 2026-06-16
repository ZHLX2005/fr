import 'dart:async';
import 'dart:io';

import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import 'models/localnet_config.dart';
import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/config_service.dart';
import 'services/debug_log_service.dart';

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

  // ============ 消息列表（兼容旧 LocalnetMessage 模型） ============

  final List<LocalnetMessage> _messages = [];
  final _messagesController =
      StreamController<List<LocalnetMessage>>.broadcast();
  Stream<List<LocalnetMessage>> get messagesStream =>
      _messagesController.stream;
  List<LocalnetMessage> get messages => List.unmodifiable(_messages);

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
      final fwCfg = fw.FrameworkConfig(
        deviceAlias: cfg.deviceAlias,
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
      // 添加到本地消息列表
      _messages.add(LocalnetMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        senderId: _fw.myDeviceId,
        senderAlias: _fw.myAlias,
        content: content,
        timestamp: DateTime.now(),
      ));
      _messagesController.add(List.unmodifiable(_messages));
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
      _messages.add(LocalnetMessage(
        id: msg.timestamp.millisecondsSinceEpoch.toString(),
        senderId: msg.sourceDeviceId,
        senderAlias: msg.payload['alias'] as String? ?? msg.sourceDeviceId,
        content: msg.payload['text'] as String? ?? '',
        timestamp: msg.timestamp,
      ));
      _messagesController.add(List.unmodifiable(_messages));
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

  Future<String?> _detectLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.')) return ip;
        }
      }
    } catch (_) {}
    return null;
  }
}

final localnetService = LocalnetService();
