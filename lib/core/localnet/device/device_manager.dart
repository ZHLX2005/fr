import 'dart:async';

import '../discovery/discovery_service.dart';
import '../discovery/remote_endpoint.dart';
import '../event_bus/event_bus.dart';
import '../event_bus/lan_event.dart';
import 'device.dart';
import 'device_registry.dart';

/// 设备管理器
///
/// 职责：
/// 1. 维护设备表（deviceId → Device）
/// 2. 通过注入的 DiscoveryService 接收端点变化，添加新设备或更新已知设备
/// 3. 定期清理离线设备（cleanupNow）
/// 4. 通过 EventBus 发射 DeviceFound / DeviceLost / DeviceUpdated
class DeviceManager {
  DeviceManager({
    required EventBus eventBus,
    required this.myDeviceId,
    this.myAlias = '',
    this.timeout = const Duration(seconds: 15),
    DiscoveryService? discovery,
  })  : _bus = eventBus,
        _registry = DeviceRegistry(),
        _discovery = discovery;

  final EventBus _bus;
  final DeviceRegistry _registry;
  // ignore: unused_field
  DiscoveryService? _discovery;
  StreamSubscription<List<RemoteEndpoint>>? _discoverySub;
  final String myDeviceId;
  final String myAlias;
  final Duration timeout;

  /// 当前所有设备（不可变列表）
  List<Device> get devices => _registry.all;

  /// 设备数
  int get deviceCount => _registry.length;

  /// 获取单个设备
  Device? getDevice(String deviceId) => _registry.get(deviceId);

  /// 注入 DiscoveryService（在 framework 启动时调用）
  void attachDiscovery(DiscoveryService discovery) {
    _discovery = discovery;
    _discoverySub?.cancel();
    _discoverySub = discovery.watch().listen(_onDiscoveryUpdate);
  }

  void _onDiscoveryUpdate(List<RemoteEndpoint> endpoints) {
    for (final ep in endpoints) {
      if (ep.deviceId == myDeviceId) continue;
      final existing = _registry.get(ep.deviceId);
      if (existing == null) {
        final device = Device(
          deviceId: ep.deviceId,
          alias: ep.alias,
          ip: ep.address.split(':').first,
          port: int.tryParse(ep.address.split(':').last) ?? 0,
          lastSeen: ep.lastSeen,
          extras: const {},
        );
        _registry.add(device);
        _bus.emit(DeviceFoundEvent(deviceId: ep.deviceId, alias: device.alias));
      } else {
        _registry.add(existing.copyWith(lastSeen: ep.lastSeen, alias: ep.alias));
      }
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

  /// 直接添加一台设备（手动注册，不通过 discovery）
  ///
  /// 用于 Relay 模式：joinRoom 后立即注册对端设备
  void addDevice(Device device) {
    final existing = _registry.get(device.deviceId);
    _registry.add(device);
    if (existing == null) {
      _bus.emit(DeviceFoundEvent(deviceId: device.deviceId, alias: device.alias));
    } else {
      _bus.emit(DeviceUpdatedEvent(deviceId: device.deviceId, alias: device.alias));
    }
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
    await _discoverySub?.cancel();
    _registry.clear();
  }
}
