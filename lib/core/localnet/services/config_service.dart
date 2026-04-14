import '../models/localnet_config.dart';
import 'debug_log_service.dart';

class ConfigService {
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;
  ConfigService._internal();

  LocalnetConfig _config = const LocalnetConfig();
  bool _initialized = false;

  LocalnetConfig get config => _config;
  bool get initialized => _initialized;

  /// 日志状态机状态
  static const String stateInit = 'INIT';
  static const String stateLoading = 'LOADING';
  static const String stateReady = 'READY';
  static const String stateError = 'ERROR';

  String _serviceState = stateInit;
  String get serviceState => _serviceState;

  Future<void> init() async {
    if (_initialized) return;

    debugLog.logState('Config', _serviceState, stateLoading, note: '加载配置');
    _serviceState = stateLoading;

    try {
      _config = await LocalnetConfig.load();
      _initialized = true;
      debugLog.logState(
        'Config',
        _serviceState,
        stateReady,
        note: '配置加载完成: ${_config.toString()}',
      );
      _serviceState = stateReady;
    } catch (e) {
      debugLog.logState(
        'Config',
        _serviceState,
        stateError,
        note: '配置加载失败: $e',
      );
      _serviceState = stateError;
    }
  }

  Future<void> updateConfig(LocalnetConfig newConfig) async {
    final oldConfig = _config;
    _config = newConfig;
    await _config.save();
    debugLog.i(
      'Config',
      '配置已更新: ${oldConfig.deviceAlias} → ${_config.deviceAlias}',
    );
    debugLog.i(
      'Config',
      '  UDP广播: ${oldConfig.udpBroadcastEnabled} → ${_config.udpBroadcastEnabled}',
    );
    debugLog.i(
      'Config',
      '  UDP监听: ${oldConfig.udpListenerEnabled} → ${_config.udpListenerEnabled}',
    );
    debugLog.i(
      'Config',
      '  HTTP服务: ${oldConfig.httpServerEnabled} → ${_config.httpServerEnabled}',
    );
    debugLog.i('Config', '  Port: ${oldConfig.port} → ${_config.port}');
  }

  Future<void> reset() async {
    _config = const LocalnetConfig();
    await _config.save();
    debugLog.i('Config', '配置已重置为默认值');
  }
}

final configService = ConfigService();
