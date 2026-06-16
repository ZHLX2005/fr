import 'dart:async';

import '../device/device_manager.dart';
import '../event_bus/event_bus.dart';
import '../event_bus/lan_event.dart';
import 'connection_quality.dart';

/// 连接管理器
///
/// 职责：
/// 1. 监听 DeviceEvent（Found / Lost / Updated）→ 维护每个设备的 ConnectionQuality
/// 2. 提供 isOnline / getQuality / markReconnecting API
/// 3. 发射 ConnectionStateEvent（Online / Offline / Reconnecting / ReconnectFailed）
class ConnectionManager {
  ConnectionManager({
    required EventBus eventBus,
    required DeviceManager deviceManager,
    this.grace = const Duration(seconds: 3),
  })  : _bus = eventBus,
        _deviceMgr = deviceManager;

  final EventBus _bus;
  final DeviceManager _deviceMgr;
  final Duration grace;

  final Map<String, ConnectionQuality> _qualities = {};
  StreamSubscription<DeviceFoundEvent>? _foundSub;
  StreamSubscription<DeviceLostEvent>? _lostSub;

  bool _started = false;

  /// 启动：订阅 DeviceEvent
  Future<void> start() async {
    if (_started) return;
    _foundSub = _bus.watch<DeviceFoundEvent>().listen(_onFound);
    _lostSub = _bus.watch<DeviceLostEvent>().listen(_onLost);
    _started = true;
  }

  /// 停止
  Future<void> stop() async {
    await _foundSub?.cancel();
    await _lostSub?.cancel();
    _foundSub = null;
    _lostSub = null;
    _qualities.clear();
    _started = false;
  }

  /// 设备是否在线
  bool isOnline(String deviceId) =>
      _qualities[deviceId] == ConnectionQuality.online ||
      _qualities[deviceId] == ConnectionQuality.degraded;

  /// 获取设备连接质量
  ConnectionQuality getQuality(String deviceId) =>
      _qualities[deviceId] ?? ConnectionQuality.unknown;

  /// 标记设备为重连中
  void markReconnecting(String deviceId) {
    if (_deviceMgr.getDevice(deviceId) == null) return;
    _qualities[deviceId] = ConnectionQuality.degraded;
    _bus.emit(DeviceReconnectingEvent(deviceId: deviceId));
  }

  /// 标记设备重连失败
  void markReconnectFailed(String deviceId, {int attempts = 0}) {
    _qualities[deviceId] = ConnectionQuality.offline;
    _bus.emit(DeviceReconnectFailedEvent(
      deviceId: deviceId,
      attempts: attempts,
    ));
  }

  void _onFound(DeviceFoundEvent e) {
    _qualities[e.deviceId] = ConnectionQuality.online;
    _bus.emit(DeviceOnlineEvent(deviceId: e.deviceId));
  }

  void _onLost(DeviceLostEvent e) {
    _qualities[e.deviceId] = ConnectionQuality.offline;
    _bus.emit(DeviceOfflineEvent(deviceId: e.deviceId));
  }
}
