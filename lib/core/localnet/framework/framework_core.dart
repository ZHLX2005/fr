import '../discovery/discovery_service.dart';
import '../transport_service/transport_service.dart';
import '../device/device_manager.dart';
import '../connection/connection_manager.dart';
import '../session/session_manager.dart';
import '../event_bus/event_bus.dart';

/// 框架核心抽象父类 — 统一管理发现 + 传输 + 设备 + 连接生命周期
///
/// [FrameworkLanCore] 和 [FrameworkRelayCore] 各自实现：
///
/// 生命周期：
/// 1. [start] — 按依赖顺序初始化所有子模块（discovery → managers → transport）
/// 2. [stop]  — 反序关闭
/// 3. [dispose] — [stop] + 释放资源（eventBus, controllers）
abstract class FrameworkCore {
  /// 发现服务（LAN: UDP 多播 / Relay: HTTP 房间 API）
  DiscoveryService get discovery;

  /// 传输服务（LAN: HTTP P2P / Relay: WS 帧）
  TransportService get transport;

  /// 设备管理器
  DeviceManager get deviceManager;

  /// 连接管理器
  ConnectionManager get connectionManager;

  /// 会话管理器（自动状态同步）
  SessionManager get sessionManager;

  /// 事件总线
  EventBus get eventBus;

  /// 是否已启动
  bool get isRunning;

  /// 启动框架
  Future<void> start();

  /// 停止框架
  Future<void> stop();

  /// 销毁框架（stop + 释放资源）
  Future<void> dispose();
}
