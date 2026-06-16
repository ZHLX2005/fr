part of 'lan_event.dart';
// 设备模型在 Task 6 定义，此处先 import 占位
// 实际实现时会调整 import

sealed class DeviceEvent extends LanEvent {
  const DeviceEvent();
  String get deviceId;
}

class DeviceFoundEvent extends DeviceEvent {
  const DeviceFoundEvent({required this.deviceId, required this.alias});
  @override
  final String deviceId;
  final String alias;
}

class DeviceLostEvent extends DeviceEvent {
  const DeviceLostEvent({required this.deviceId});
  @override
  final String deviceId;
}

class DeviceUpdatedEvent extends DeviceEvent {
  const DeviceUpdatedEvent({required this.deviceId, required this.alias});
  @override
  final String deviceId;
  final String alias;
}
