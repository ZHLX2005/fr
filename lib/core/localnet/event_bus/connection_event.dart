part of 'lan_event.dart';

sealed class ConnectionStateEvent extends LanEvent {
  const ConnectionStateEvent({required this.deviceId});
  final String deviceId;
}

class DeviceOnlineEvent extends ConnectionStateEvent {
  const DeviceOnlineEvent({required super.deviceId});
}

class DeviceOfflineEvent extends ConnectionStateEvent {
  const DeviceOfflineEvent({required super.deviceId});
}

class DeviceReconnectingEvent extends ConnectionStateEvent {
  const DeviceReconnectingEvent({required super.deviceId});
}

class DeviceReconnectFailedEvent extends ConnectionStateEvent {
  const DeviceReconnectFailedEvent({required super.deviceId, required this.attempts});
  final int attempts;
}
