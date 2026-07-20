import 'dart:async';

import '../channel/channel_manager.dart';
import '../connection/connection_manager.dart';
import '../device/device_manager.dart';
import '../discovery/lan_discovery.dart';
import '../event_bus/event_bus.dart';
import '../session/session_manager.dart';
import '../transport/http_transport.dart';
import '../transport/transport_config.dart';
import '../transport/udp_transport.dart';
import '../transport_service/lan_transport_service.dart';
import '../transport_service/transport_service.dart';
import 'framework_core.dart';

/// LAN 后端的 FrameworkCore — UDP 多播发现 + HTTP P2P 传输
///
/// 实现 [FrameworkCore] 抽象父类：
/// - [discovery]: [LanDiscovery]（UDP 多播心跳）
/// - [transport]: [LanTransportService]（HTTP P2P）
/// - [deviceManager], [connectionManager], [sessionManager], [eventBus]
class FrameworkLanCore implements FrameworkCore {
  FrameworkLanCore({
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

  // ============ FrameworkCore 接口实现 ============

  @override
  final EventBus eventBus = EventBus();

  @override
  late final LanDiscovery discovery;
  late final UdpTransport udpTransport;
  late final HttpTransport httpTransport;
  late final ChannelManager channelManager;
  @override
  late final DeviceManager deviceManager;
  @override
  late final ConnectionManager connectionManager;
  @override
  late final SessionManager sessionManager;
  @override
  late final TransportService transport;

  final StreamController<String> _multicastController =
      StreamController<String>.broadcast();

  /// 业务多播通道（任意 string payload）
  Stream<String> get multicasts => _multicastController.stream;

  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  bool _isRunning = false;

  @override
  bool get isRunning => _isRunning;

  /// 启动（幂等）
  @override
  Future<void> start() async {
    if (_isRunning) return;

    // 0. 守卫：UDP 与 HTTP 均禁用时启动毫无意义
    if (!transportConfig.enableUdp && !transportConfig.enableHttp) {
      throw StateError(
        'FrameworkLanCore.start() 拒绝启动：UDP 与 HTTP 均被禁用，'
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

    // 3. 创建并启动 LanDiscovery
    discovery = LanDiscovery(
      myDeviceId: myDeviceId,
      myAlias: myAlias,
      udp: udpTransport,
    );
    deviceManager = DeviceManager(
      eventBus: eventBus,
      myDeviceId: myDeviceId,
      myAlias: myAlias,
      timeout: deviceTimeout,
    );
    deviceManager.attachDiscovery(discovery);
    await discovery.start();

    // 4. ChannelManager
    channelManager = ChannelManager(
      eventBus: eventBus,
      deviceManager: deviceManager,
      transport: httpTransport,
    );
    await channelManager.start();

    // 5. LanTransportService（薄包装 ChannelManager）
    final lanTransport = LanTransportService(
      eventBus: eventBus,
      deviceManager: deviceManager,
      channelManager: channelManager,
    );
    lanTransport.start();
    transport = lanTransport;

    // 6. ConnectionManager
    connectionManager = ConnectionManager(
      eventBus: eventBus,
      deviceManager: deviceManager,
    );
    await connectionManager.start();

    // 7. SessionManager
    sessionManager = SessionManager(
      channelManager: channelManager,
      eventBus: eventBus,
    );

    // 8. 串联：UDP 业务多播 → 业务事件总线
    if (transportConfig.enableUdp) {
      udpTransport.datagrams.listen((dg) {
        final text = String.fromCharCodes(dg.data);
        if (text.trimLeft().startsWith('{')) {
          _multicastController.add(text);
          return;
        }
      });
    }

    // 9. 周期性 UDP 多播广播本机存在
    if (transportConfig.enableUdp && udpBroadcastEnabled) {
      _sendBroadcast();
      _broadcastTimer = Timer.periodic(
        broadcastInterval,
        (_) => _sendBroadcast(),
      );
    }

    // 10. 周期性清理离线设备
    _cleanupTimer = Timer.periodic(cleanupInterval, (_) {
      deviceManager.cleanupNow();
    });

    _isRunning = true;
  }

  /// 发送一次 UDP 多播广播，宣告本机存在
  void _sendBroadcast() {
    if (!udpTransport.isRunning) return;
    udpTransport.send(
      myDeviceId,
      transportConfig.httpPort,
      <String>['alias:$myAlias'],
    );
  }

  /// 停止
  @override
  Future<void> stop() async {
    if (!_isRunning) return;

    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    // 反序关闭
    await sessionManager.dispose();
    await connectionManager.stop();
    await channelManager.stop();
    await discovery.stop();
    await deviceManager.dispose();

    // 停止 TransportService
    if (transport is LanTransportService) {
      (transport as LanTransportService).dispose();
    }

    if (transportConfig.enableHttp) {
      await httpTransport.stop();
    }
    if (transportConfig.enableUdp) {
      await udpTransport.stop();
    }

    _isRunning = false;
  }

  /// 销毁
  @override
  Future<void> dispose() async {
    await stop();
    eventBus.dispose();
    await _multicastController.close();
  }
}
