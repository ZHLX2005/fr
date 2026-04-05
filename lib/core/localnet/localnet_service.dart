import 'models/localnet_config.dart';
import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/config_service.dart';
import 'services/debug_log_service.dart';
import 'services/discovery_service.dart';
import 'services/message_service.dart';

/// LocalNet 服务 - 第一阶段：仅设备发现
class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  final ConfigService config = configService;
  late DiscoveryService discovery;
  late MessageService message;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// 状态
  static const String stateInit = 'INIT';
  static const String stateIdle = 'IDLE';
  static const String stateStarting = 'STARTING';
  static const String stateRunning = 'RUNNING';
  static const String stateStopping = 'STOPPING';
  static const String stateError = 'ERROR';

  String _serviceState = stateInit;
  String get serviceState => _serviceState;

  String get deviceAlias => config.config.deviceAlias;

  String get deviceId => discovery.deviceId;

  /// 各组件运行状态
  bool get isUdpBroadcastRunning => discovery.isUdpBroadcastRunning;
  bool get isUdpListenerRunning => discovery.isUdpListenerRunning;
  bool get isHttpServerRunning => discovery.isHttpServerRunning;

  void _logState(String from, String to, {String? note}) {
    debugLog.logState('Localnet', from, to, note: note);
  }

  /// 初始化
  Future<void> init() async {
    if (_initialized) return;

    _logState(_serviceState, stateStarting, note: '初始化');
    _serviceState = stateStarting;

    // 加载配置
    await config.init();

    // 创建设备发现服务
    discovery = DiscoveryService();

    // 创建消息服务（暂时不启用 HTTP 服务器）
    message = MessageService(
      deviceId: discovery.deviceId,
      deviceAlias: config.config.deviceAlias,
    );

    _initialized = true;
    _logState(_serviceState, stateIdle, note: '初始化完成');
    _serviceState = stateIdle;
  }

  /// 应用配置
  Future<void> applyConfig() async {
    final cfg = config.config;
    discovery.deviceAlias = cfg.deviceAlias;
    discovery.devicePort = cfg.port;
    message.updateAlias(cfg.deviceAlias);
    message.updatePort(cfg.port);
    debugLog.i('Localnet', '配置已应用: ${cfg.deviceAlias} :${cfg.port}');
  }

  /// 启动服务
  Future<void> start() async {
    if (!_initialized) {
      await init();
    }

    _logState(_serviceState, stateStarting, note: '启动服务');
    _serviceState = stateStarting;

    try {
      // 应用配置
      await applyConfig();

      final cfg = config.config;

      // 根据配置启动各组件
      if (cfg.httpServerEnabled) {
        await discovery.startHttpServer();
      }
      if (cfg.udpListenerEnabled) {
        await discovery.startUdpListener();
      }
      if (cfg.udpBroadcastEnabled) {
        discovery.startUdpBroadcast();
      }

      // 只有开启了至少一个网络功能，才启动清理定时器
      final hasNetworkFeature = cfg.httpServerEnabled || cfg.udpListenerEnabled || cfg.udpBroadcastEnabled;
      if (hasNetworkFeature) {
        discovery.startCleanupTimer();
      }

      // 注册消息回调（消息通过 discovery 的 HTTP 服务器接收）
      discovery.onMessageReceived = (msg) {
        message.addReceivedMessage(msg);
      };

      _logState(_serviceState, stateRunning, note: '服务已启动');
      _serviceState = stateRunning;
    } catch (e) {
      debugLog.e('Localnet', '启动失败: $e');
      _logState(_serviceState, stateError, note: '启动失败: $e');
      _serviceState = stateError;
    }
  }

  /// 停止服务
  void stop() {
    if (_serviceState != stateRunning && _serviceState != stateStarting) {
      debugLog.w('Localnet', '服务未运行');
      return;
    }

    _logState(_serviceState, stateStopping, note: '停止服务');
    _serviceState = stateStopping;

    discovery.stop();
    message.stop();

    _logState(_serviceState, stateIdle, note: '服务已停止');
    _serviceState = stateIdle;
  }

  // ========== 组件独立控制 ==========

  /// 启动 UDP 广播
  Future<void> startUdpBroadcast() async {
    if (!discovery.isUdpListenerRunning) {
      await discovery.startUdpListener();
    }
    discovery.startUdpBroadcast();
  }

  /// 停止 UDP 广播
  void stopUdpBroadcast() {
    discovery.stopUdpBroadcast();
  }

  /// 启动 UDP 监听
  Future<void> startUdpListener() async {
    await discovery.startUdpListener();
  }

  /// 停止 UDP 监听
  void stopUdpListener() {
    discovery.stopUdpListener();
  }

  /// 启动 HTTP 服务器
  Future<void> startHttpServer() async {
    await discovery.startHttpServer();
  }

  /// 停止 HTTP 服务器
  void stopHttpServer() {
    discovery.stopHttpServer();
  }

  void dispose() {
    stop();
    discovery.dispose();
    message.dispose();
  }

  List<LocalnetDevice> get devices => discovery.devices;
  Stream<List<LocalnetDevice>> get devicesStream => discovery.devicesStream;

  List<LocalnetMessage> get messages => message.messages;
  Stream<List<LocalnetMessage>> get messagesStream => message.messagesStream;

  Future<bool> sendMessage(LocalnetDevice target, String content) {
    return message.sendMessage(target, content);
  }

  /// 更新配置
  Future<void> updateConfig(LocalnetConfig newConfig) async {
    await config.updateConfig(newConfig);
    await applyConfig();

    if (_serviceState == stateRunning) {
      debugLog.i('Localnet', '配置已更改，重启服务...');
      stop();
      await start();
    }
  }
}

final localnetService = LocalnetService();
