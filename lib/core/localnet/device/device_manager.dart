import 'dart:async';

import '../event_bus/event_bus.dart';
import '../event_bus/lan_event.dart';
import 'device.dart';
import 'device_registry.dart';

/// 设备管理器
///
/// 职责：
/// 1. 维护设备表（deviceId → Device）
/// 2. 接收 UDP 多播数据报（onDatagram），添加新设备或更新已知设备
/// 3. 定期清理离线设备（cleanupNow）
/// 4. 通过 EventBus 发射 DeviceFound / DeviceLost / DeviceUpdated
class DeviceManager {
  DeviceManager({
    required EventBus eventBus,
    required this.myDeviceId,
    this.myAlias = '',
    this.timeout = const Duration(seconds: 15),
  })  : _bus = eventBus,
        _registry = DeviceRegistry();

  final EventBus _bus;
  final DeviceRegistry _registry;
  final String myDeviceId;
  final String myAlias;
  final Duration timeout;

  /// 当前所有设备（不可变列表）
  List<Device> get devices => _registry.all;

  /// 设备数
  int get deviceCount => _registry.length;

  /// 获取单个设备
  Device? getDevice(String deviceId) => _registry.get(deviceId);

  /// 收到 UDP 数据报
  ///
  /// 由 UdpTransport 的 datagram stream 回调。
  void onDatagram({
    required String deviceId,
    required String ip,
    required int port,
    Map<String, String> extras = const {},
  }) {
    if (deviceId == myDeviceId) return; // 忽略自己

    final existing = _registry.get(deviceId);
    final now = DateTime.now();
    final device = Device(
      deviceId: deviceId,
      alias: existing?.alias ?? ip, // 默认用 ip 当 alias，第一次见到
      ip: ip,
      port: port,
      lastSeen: now,
      extras: extras.isEmpty ? (existing?.extras ?? const {}) : extras,
    );

    if (existing == null) {
      _registry.add(device);
      _bus.emit(DeviceFoundEvent(deviceId: deviceId, alias: device.alias));
    } else {
      _registry.add(device); // 重复 add 自动覆盖
      // 只在 lastSeen 更新（不需要每次都发事件）
    }
  }

  /// 更新设备别名
  void updateAlias(String deviceId, String newAlias) {
    final existing = _registry.get(deviceId);
    if (existing == null) return;
    final updated = existing.copyWith(alias: newAlias);
    _registry.add(updated);
    _bus.emit(DeviceUpdatedEvent(deviceId: deviceId, alias: newAlias));
  }

  /// 主动移除设备
  void remove(String deviceId) {
    _registry.remove(deviceId);
    _bus.emit(DeviceLostEvent(deviceId: deviceId));
  }

  /// 立即清理离线设备
  /// 返回被清理的设备 id 列表
  List<String> cleanupNow() {
    final removed = _registry.cleanupStale(timeout: timeout);
    for (final id in removed) {
      _bus.emit(DeviceLostEvent(deviceId: id));
    }
    return removed;
  }

  /// 测试辅助：强制修改某设备的 lastSeen
  void debugForceLastSeen(String deviceId, DateTime ts) {
    final d = _registry.get(deviceId);
    if (d == null) return;
    _registry.add(d.copyWith(lastSeen: ts));
  }

  /// 销毁
  Future<void> dispose() async {
    _registry.clear();
  }
}
