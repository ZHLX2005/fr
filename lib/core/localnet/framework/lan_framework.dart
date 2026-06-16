import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../channel/channel_manager.dart';
import '../channel/channel_message.dart';
import '../channel/send_result.dart';
import '../connection/connection_manager.dart';
import '../connection/connection_quality.dart';
import '../device/device.dart';
import '../event_bus/event_bus.dart';
import '../event_bus/lan_event.dart';
import 'exception/framework_exception.dart';
import 'framework_config.dart';
import 'framework_core.dart';
import 'framework_status.dart';

/// 局域网通信框架（单例门面）
///
/// 业务侧唯一接触点。所有 LAN 通信都通过这个类。
class LanFramework {
  LanFramework._();
  static final LanFramework instance = LanFramework._();

  FrameworkCore? _core;
  String _myDeviceId = '';
  String _myAlias = '';
  String? _cachedMyIp;

  FrameworkStatus _status = FrameworkStatus.init;
  FrameworkStatus get status => _status;

  /// 启动框架
  Future<void> start(FrameworkConfig config) async {
    if (_status == FrameworkStatus.running ||
        _status == FrameworkStatus.starting) {
      return; // 幂等
    }
    _status = FrameworkStatus.starting;
    _myDeviceId = config.deviceId ?? const Uuid().v4();
    _myAlias = config.deviceAlias;

    final core = FrameworkCore(
      myDeviceId: _myDeviceId,
      myAlias: _myAlias,
      transportConfig: config.toTransportConfig(),
    );

    try {
      await core.start();
      _core = core;
      _status = FrameworkStatus.running;
      core.eventBus.emit(const ServiceStartedEvent());
    } catch (e) {
      _status = FrameworkStatus.error;
      core.eventBus.emit(ServiceErrorEvent(error: e));
      rethrow;
    }
  }

  /// 停止框架
  Future<void> stop() async {
    if (_status == FrameworkStatus.init) return;
    _status = FrameworkStatus.stopping;
    final core = _core;
    if (core != null) {
      await core.stop();
      core.eventBus.emit(const ServiceStoppedEvent());
    }
    _core = null;
    _status = FrameworkStatus.init;
  }

  /// 销毁（释放 EventBus）
  Future<void> dispose() async {
    await stop();
    await _core?.dispose();
  }

  // ============ 设备发现 ============

  /// 当前所有发现的设备
  List<Device> get devices => _core?.deviceManager.devices ?? const [];

  /// 设备列表变化
  Stream<List<Device>> watchDevices() async* {
    yield devices;
    yield* _bus().watch<DeviceFoundEvent>().map((_) => devices);
    yield* _bus().watch<DeviceLostEvent>().map((_) => devices);
    yield* _bus().watch<DeviceUpdatedEvent>().map((_) => devices);
  }

  /// 单个设备事件
  Stream<DeviceEvent> watchDeviceEvents() =>
      _bus().watch<DeviceEvent>();

  // ============ 业务通道 ============

  /// 发送通道消息
  Future<SendResult> sendTo(
    String targetDeviceId,
    String channel,
    Map<String, dynamic> payload,
  ) async {
    _assertRunning();
    return _channelManager().sendTo(targetDeviceId, channel, payload);
  }

  /// 订阅通道消息
  Stream<ChannelMessage> watchChannel(String channel) {
    _assertRunning();
    return _channelManager().watchChannel(channel);
  }

  // ============ 连接状态 ============

  /// 设备是否在线
  bool isOnline(String deviceId) =>
      _connectionManager().isOnline(deviceId);

  /// 设备连接质量
  ConnectionQuality getQuality(String deviceId) =>
      _connectionManager().getQuality(deviceId);

  /// 订阅某设备的连接状态
  Stream<ConnectionStateEvent> watchConnectionState(String deviceId) async* {
    yield DeviceOnlineEvent(deviceId: deviceId);
    // 简化：实际实现应按 deviceId 过滤
  }

  // ============ 配置热更新 ============

  Future<void> updateConfig(FrameworkConfig newConfig) async {
    _assertRunning();
    final core = _core!;
    core.eventBus.emit(const ConfigChangedEvent());
    // 本轮先 stop+start；下轮可优化为热更新
    await stop();
    await start(newConfig);
  }

  // ============ 框架状态 ============

  Stream<FrameworkStatus> watchStatus() async* {
    yield _status;
  }

  /// 本机设备 ID（start 后可用）
  String get myDeviceId => _myDeviceId;

  /// 本机设备别名
  String get myAlias => _myAlias;

  /// 注册自定义 HTTP 路由
  void registerRoute(String path, Future<void> Function(HttpRequest) handler) {
    _assertRunning();
    _core!.httpTransport.registerHandler(path, handler);
  }

  /// 注销自定义 HTTP 路由
  void unregisterRoute(String path) {
    _assertRunning();
    _core!.httpTransport.unregisterHandler(path);
  }

  /// 原始事件总线（高级用户使用）
  EventBus get eventBus => _core?.eventBus ?? _nullBus;

  /// 设置本机 IP（由适配层探测后注入）
  void setMyIp(String ip) {
    _cachedMyIp = ip;
  }

  // ============ 内部辅助 ============

  EventBus _bus() {
    final core = _core;
    if (core == null) {
      throw const FrameworkNotRunningException('框架未启动');
    }
    return core.eventBus;
  }

  ChannelManager _channelManager() {
    _assertRunning();
    return _core!.channelManager;
  }

  ConnectionManager _connectionManager() {
    _assertRunning();
    return _core!.connectionManager;
  }

  void _assertRunning() {
    if (_status != FrameworkStatus.running) {
      throw const FrameworkNotRunningException('框架未运行，请先调用 start()');
    }
  }

  final EventBus _nullBus = EventBus();
}
