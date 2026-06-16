import 'dart:async';

import '../channel/channel_manager.dart';
import '../connection/connection_manager.dart';
import '../device/device_manager.dart';
import '../event_bus/event_bus.dart';
import '../transport/http_transport.dart';
import '../transport/transport_config.dart';
import '../transport/udp_transport.dart';

/// 核心编排器
///
/// 职责：
/// 1. 创建并管理所有子模块
/// 2. 启动时按依赖顺序初始化；停止时反序关闭
/// 3. 串联 UdpTransport → DeviceManager
/// 4. 暴露 eventBus / deviceManager / channelManager / connectionManager 给上层
class FrameworkCore {
  FrameworkCore({
    required this.myDeviceId,
    this.myAlias = '',
    this.transportConfig = const TransportConfig(),
  });

  final String myDeviceId;
  final String myAlias;
  final TransportConfig transportConfig;

  final EventBus eventBus = EventBus();

  late final UdpTransport udpTransport;
  late final HttpTransport httpTransport;
  late final DeviceManager deviceManager;
  late final ChannelManager channelManager;
  late final ConnectionManager connectionManager;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// 启动（幂等）
  Future<void> start() async {
    if (_isRunning) return;

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

    // 4. 串联：UDP 收到的多播 → DeviceManager
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

    _isRunning = true;
  }

  /// 停止
  Future<void> stop() async {
    if (!_isRunning) return;

    // 反序关闭
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
