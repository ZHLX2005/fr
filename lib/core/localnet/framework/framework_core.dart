import 'dart:async';

import '../channel/channel_manager.dart';
import '../connection/connection_manager.dart';
import '../device/device_manager.dart';
import '../event_bus/event_bus.dart';
import '../session/session_manager.dart';
import '../transport/http_transport.dart';
import '../transport/transport_config.dart';
import '../transport/udp_transport.dart';

/// 核心编排器
///
/// 职责：
/// 1. 创建并管理所有子模块
/// 2. 启动时按依赖顺序初始化；停止时反序关闭
/// 3. 串联 UdpTransport → DeviceManager
/// 4. 周期性 UDP 多播广播本机存在（设备发现的心跳）
/// 5. 周期性清理离线设备
/// 6. 暴露 eventBus / deviceManager / channelManager / connectionManager 给上层
class FrameworkCore {
  FrameworkCore({
    required this.myDeviceId,
    this.myAlias = '',
    this.transportConfig = const TransportConfig(),
    this.udpBroadcastEnabled = true,
    this.broadcastInterval = const Duration(seconds: 3),
    this.deviceTimeout = const Duration(seconds: 15),
    this.cleanupInterval = const Duration(seconds: 10),
  });

  final String myDeviceId;
  final String myAlias;
  final TransportConfig transportConfig;
  final bool udpBroadcastEnabled;
  final Duration broadcastInterval;
  final Duration deviceTimeout;
  final Duration cleanupInterval;

  final EventBus eventBus = EventBus();

  late final UdpTransport udpTransport;
  late final HttpTransport httpTransport;
  late final DeviceManager deviceManager;
  late final ChannelManager channelManager;
  late final ConnectionManager connectionManager;
  late final SessionManager sessionManager;

  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// 启动（幂等）
  Future<void> start() async {
    if (_isRunning) return;

    // 0. 守卫：UDP 与 HTTP 均禁用时启动毫无意义，直接报错而非误报 RUNNING
    if (!transportConfig.enableUdp && !transportConfig.enableHttp) {
      throw StateError(
        'FrameworkCore.start() 拒绝启动：UDP 与 HTTP 均被禁用，'
        '请在配置中至少开启一项。',
      );
    }

    // 1. 创建 transport
    udpTransport = UdpTransport(config: transportConfig);
    httpTransport = HttpTransport(config: transportConfig);

    // 2. 启动 transport
    if (transportConfig.enableUdp) {
      await udpTransport.start();
    }
    if (transportConfig.enableHttp) {
      await httpTransport.start();
    }

    // 3. 创建并启动 manager
    deviceManager = DeviceManager(
      eventBus: eventBus,
      myDeviceId: myDeviceId,
      myAlias: myAlias,
      timeout: deviceTimeout,
    );

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
    await connectionManager.start();

    // 4. 创建 SessionManager
    sessionManager = SessionManager(
      channelManager: channelManager,
      eventBus: eventBus,
    );

    // 5. 串联：UDP 收到的多播 → DeviceManager
    if (transportConfig.enableUdp) {
      udpTransport.datagrams.listen((dg) {
        final text = String.fromCharCodes(dg.data);
        // 格式: "deviceId,port" 或 "deviceId,port,key:value,..."
        final parts = text.split(',');
        if (parts.length < 2) return;
        final id = parts[0].trim();
        final port = int.tryParse(parts[1].trim());
        if (id.isEmpty || port == null) return;

        final extras = <String, String>{};
        for (var i = 2; i < parts.length; i++) {
          final kv = parts[i].split(':');
          if (kv.length == 2) {
            extras[kv[0].trim()] = kv[1].trim();
          }
        }

        deviceManager.onDatagram(
          deviceId: id,
          ip: dg.senderAddress.address,
          port: port,
          extras: extras,
        );
      });
    }

    // 6. 周期性 UDP 多播广播本机存在（设备发现的心跳）
    if (transportConfig.enableUdp && udpBroadcastEnabled) {
      _sendBroadcast(); // 启动时立即广播一次，缩短首次发现延迟
      _broadcastTimer = Timer.periodic(
        broadcastInterval,
        (_) => _sendBroadcast(),
      );
    }

    // 7. 周期性清理离线设备
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) {
      deviceManager.cleanupNow();
    });

    _isRunning = true;
  }

  /// 发送一次 UDP 多播广播，宣告本机存在
  ///
  /// 报文格式: `deviceId,httpPort,alias:<别名>`
  void _sendBroadcast() {
    if (!udpTransport.isRunning) return;
    udpTransport.send(
      myDeviceId,
      transportConfig.httpPort,
      <String>['alias:$myAlias'],
    );
  }

  /// 停止
  Future<void> stop() async {
    if (!_isRunning) return;

    // 先停定时器，避免停止过程中再触发广播/清理
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    // 反序关闭
    await sessionManager.dispose();
    await connectionManager.stop();
    await channelManager.stop();
    await deviceManager.dispose();

    if (transportConfig.enableHttp) {
      await httpTransport.stop();
    }
    if (transportConfig.enableUdp) {
      await udpTransport.stop();
    }

    _isRunning = false;
  }

  /// 销毁
  Future<void> dispose() async {
    await stop();
    eventBus.dispose();
  }
}
