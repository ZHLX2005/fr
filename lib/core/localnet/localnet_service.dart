import 'models/localnet_config.dart';
import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/config_service.dart';
import 'services/debug_log_service.dart';
import 'services/discovery_service.dart';
import 'services/message_service.dart';

class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  final ConfigService config = configService;
  late DiscoveryService discovery;
  late MessageService message;

  bool _initialized = false;

  bool get isInitialized => _initialized;

  String get deviceAlias => config.config.deviceAlias;

  String get deviceId => discovery.deviceId;

  /// 日志状态机状态
  static const String stateInit = 'INIT';
  static const String stateIdle = 'IDLE';
  static const String stateStarting = 'STARTING';
  static const String stateRunning = 'RUNNING';
  static const String stateStopping = 'STOPPING';
  static const String stateError = 'ERROR';

  String _serviceState = stateInit;
  String get serviceState => _serviceState;

  void _logState(String from, String to, {String? note}) {
    debugLog.logState('Localnet', from, to, note: note);
  }

  Future<void> init() async {
    if (_initialized) return;

    _logState(_serviceState, stateStarting, note: '初始化配置');
    _serviceState = stateStarting;

    // 加载配置
    await config.init();

    // 使用配置初始化服务
    final cfg = config.config;
    discovery = DiscoveryService();
    message = MessageService(
      deviceId: discovery.deviceId,
      deviceAlias: cfg.deviceAlias,
    );

    // 应用配置
    await applyConfig();

    _initialized = true;
    _logState(_serviceState, stateIdle, note: '初始化完成');
    _serviceState = stateIdle;
  }

  Future<void> applyConfig() async {
    final cfg = config.config;

    // 更新设备别名
    discovery.deviceAlias = cfg.deviceAlias;
    message.updateAlias(cfg.deviceAlias);

    // 更新端口
    discovery.updatePort(cfg.port);
    message.updatePort(cfg.port);

    debugLog.i('Localnet', '配置已应用到服务: ${cfg.toString()}');
  }

  Future<void> start() async {
    if (!_initialized) {
      await init();
    }

    _logState(_serviceState, stateStarting, note: '启动服务');
    _serviceState = stateStarting;

    final cfg = config.config;

    try {
      // 根据配置决定启动哪些服务
      if (cfg.httpEnabled) {
        debugLog.i('Localnet', '启动 HTTP 服务器...');
        await message.startServer();
      } else {
        debugLog.i('Localnet', 'HTTP 服务器已禁用，跳过');
      }

      if (cfg.multicastEnabled) {
        debugLog.i('Localnet', '启动 UDP 多播发现...');
        await discovery.startListening();
      } else {
        debugLog.i('Localnet', 'UDP 多播已禁用，跳过');
      }

      _logState(_serviceState, stateRunning, note: '服务已启动');
      _serviceState = stateRunning;
    } catch (e) {
      debugLog.e('Localnet', '启动失败: $e');
      _logState(_serviceState, stateError, note: '启动失败: $e');
      _serviceState = stateError;
    }
  }

  void stop() {
    if (_serviceState != stateRunning && _serviceState != stateStarting) {
      debugLog.w('Localnet', '服务未运行，无法停止');
      return;
    }

    _logState(_serviceState, stateStopping, note: '停止服务');
    _serviceState = stateStopping;

    discovery.stop();
    message.stop();

    _logState(_serviceState, stateIdle, note: '服务已停止');
    _serviceState = stateIdle;
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

  Future<void> updateConfig(LocalnetConfig newConfig) async {
    await config.updateConfig(newConfig);
    await applyConfig();

    // 如果服务正在运行，需要重启以应用新配置
    if (_serviceState == stateRunning) {
      debugLog.i('Localnet', '配置已更改，重启服务以应用...');
      stop();
      await start();
    }
  }
}

final localnetService = LocalnetService();
