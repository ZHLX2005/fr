import 'dart:io';

import 'models/localnet_config.dart';
import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/config_service.dart';
import 'services/debug_log_service.dart';
import 'services/discovery_service.dart';
import 'services/message_service.dart';
import '../../core/surround_game/surround_game_service.dart' show surroundGameService;

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

    // 幂等保护：服务已在运行就不重入。
    // 多个入口（discover_page.initState / game_lobby_page.initState / 刷新按钮）
    // 会反复调 start()，但组件层（HttpServer/_udpSocket）已自带 null-check 保护，
    // 真正重复跑只会触发多余的状态机转换日志和 applyConfig。
    if (_serviceState == stateRunning) {
      debugLog.d('Localnet', '服务已在运行，跳过 start()');
      return;
    }
    if (_serviceState == stateStarting) {
      debugLog.d('Localnet', '服务正在启动中，等待完成');
      // 简单做法：等现有启动完成。生产环境可用 Completer 复用 Future
      return;
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
      final hasNetworkFeature =
          cfg.httpServerEnabled ||
          cfg.udpListenerEnabled ||
          cfg.udpBroadcastEnabled;
      if (hasNetworkFeature) {
        discovery.startCleanupTimer();
      }

      // 注册消息回调（消息通过 discovery 的 HTTP 服务器接收）
      discovery.onMessageReceived = (msg) {
        message.addReceivedMessage(msg);
      };

      // 初始化围追堵截游戏服务（注册 HTTP 路由 + 传递设备信息 + 钩入广播）
      if (discovery.isHttpServerRunning) {
        final myIp = await _detectLocalIp();
        discovery.setLocalIp(myIp);

        // 模拟器场景（10.0.2.x）：设置中继到宿主机 10.0.2.2
        if (myIp != null && myIp.startsWith('10.0.2.')) {
          discovery.setRelay('10.0.2.2', 53317);
        }

        surroundGameService.init(
          registerRoute: discovery.registerRoute,
          deviceId: discovery.deviceId,
          deviceName: config.config.deviceAlias,
          myIp: myIp,
        );
        // 钩入 UDP 广播扩展
        discovery.onBuildBroadcastExtras =
            surroundGameService.buildBroadcastExtras;
        // 钩入 UDP 接收回调（接收其他设备的游戏房间）
        discovery.onUdpBroadcastReceived = (
          deviceId,
          senderIp,
          senderPort,
          extras,
        ) {
          surroundGameService.onUdpBroadcastReceived(
            deviceId: deviceId,
            senderIp: senderIp,
            senderPort: senderPort,
            extras: extras,
          );
        };
      }

      _logState(_serviceState, stateRunning, note: '服务已启动');
      _serviceState = stateRunning;
    } catch (e) {
      debugLog.e('Localnet', '启动失败: $e');
      _logState(_serviceState, stateError, note: '启动失败: $e');
      _serviceState = stateError;
    }
  }

  /// 停止服务
  Future<void> stop() async {
    if (_serviceState != stateRunning && _serviceState != stateStarting) {
      debugLog.w('Localnet', '服务未运行');
      return;
    }

    _logState(_serviceState, stateStopping, note: '停止服务');
    _serviceState = stateStopping;

    await discovery.stop();
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

  /// 释放服务
  ///
  /// 当前业务不会调到这里（discover_page.dispose 注释 keep it running），
  /// 但 stop() 内部已 async 化以正确等待 socket 关闭。
  /// TODO(future): 如果接 WidgetsBindingObserver 全局销毁流程，需把此方法
  /// 改为 `Future<void> dispose() async` 并 await stop()。
  void dispose() {
    // 同步 fire-and-forget 模式：当前没有任何调用方
    stop();
    discovery.dispose();
    message.dispose();
    _initialized = false;  // 允许重新 init
  }

  /// 探测本机局域网 IP（用于联机游戏广播）
  ///
  /// 优先返回非回环的 IPv4 地址（192.168.x.x / 10.x.x.x / 172.16-31.x.x）。
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
          // 优先选择 192.168.x.x 或 10.x.x.x
          if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
            return ip;
          }
        }
      }
      // fallback: 任意非回环 IPv4
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.address.isNotEmpty) return addr.address;
        }
      }
    } catch (e) {
      debugLog.w('Localnet', 'IP 探测失败: $e');
    }
    return null;
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
      await stop();
      await start();
    }
  }
}

final localnetService = LocalnetService();
