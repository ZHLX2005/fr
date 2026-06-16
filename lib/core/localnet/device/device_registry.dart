import 'device.dart';

/// 设备注册表（设备 id → Device）
///
/// 线程安全由外部单线程调用者保证（由 DeviceManager 串行访问）。
class DeviceRegistry {
  final Map<String, Device> _devices = {};

  /// 获取单个设备
  Device? get(String deviceId) => _devices[deviceId];

  /// 添加或更新设备（同一 deviceId 覆盖）
  void add(Device device) {
    _devices[device.deviceId] = device;
  }

  /// 移除设备
  void remove(String deviceId) {
    _devices.remove(deviceId);
  }

  /// 所有设备（不可变列表）
  List<Device> get all => List.unmodifiable(_devices.values);

  /// 当前设备数量
  int get length => _devices.length;

  /// 清空
  void clear() {
    _devices.clear();
  }

  /// 清理超时设备，返回被清理的设备 id 列表
  List<String> cleanupStale({required Duration timeout, DateTime? now}) {
    final n = now ?? DateTime.now();
    final removed = <String>[];
    _devices.removeWhere((id, d) {
      if (d.isStale(timeout: timeout, now: n)) {
        removed.add(id);
        return true;
      }
      return false;
    });
    return removed;
  }
}
