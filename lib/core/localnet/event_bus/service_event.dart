part of 'lan_event.dart';

class ServiceStartedEvent extends LanEvent {
  const ServiceStartedEvent();
}

class ServiceStoppedEvent extends LanEvent {
  const ServiceStoppedEvent();
}

class ServiceErrorEvent extends LanEvent {
  const ServiceErrorEvent({required this.error, this.stackTrace});
  final Object error;
  final StackTrace? stackTrace;
}

class ConfigChangedEvent extends LanEvent {
  const ConfigChangedEvent();
}
