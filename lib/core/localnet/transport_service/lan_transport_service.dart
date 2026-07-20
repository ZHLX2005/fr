import 'dart:async';
import 'dart:typed_data';

import '../channel/channel_manager.dart';
import '../channel/send_result.dart' as ch;
import '../device/device_manager.dart';
import '../event_bus/event_bus.dart';
import '../event_bus/lan_event.dart';
import 'transport_service.dart';

/// LAN 传输服务实现 — 基于 ChannelManager (HTTP P2P)
class LanTransportService implements TransportService {
  LanTransportService({
    required EventBus eventBus,
    required DeviceManager deviceManager,
    required ChannelManager channelManager,
  })  : _bus = eventBus,
        _deviceMgr = deviceManager,
        _channelMgr = channelManager;

  final EventBus _bus;
  final DeviceManager _deviceMgr;
  final ChannelManager _channelMgr;

  final StreamController<TransportEvent> _eventCtrl =
      StreamController<TransportEvent>.broadcast();
  StreamSubscription? _deviceSub;
  bool _subscribed = false;

  @override
  TransportConnectionState connectionState =
      TransportConnectionState.disconnected;

  @override
  String get myDeviceId => _deviceMgr.myDeviceId;

  @override
  Stream<TransportEvent> get events => _eventCtrl.stream;

  void start() {
    if (_subscribed) return;
    _subscribed = true;
    connectionState = TransportConnectionState.connected;
    _eventCtrl.add(const Connected());
    _deviceSub = _bus.watch<DeviceLostEvent>().listen((_) {});
  }

  void stop() {
    if (!_subscribed) return;
    _subscribed = false;
    _deviceSub?.cancel();
    _deviceSub = null;
    connectionState = TransportConnectionState.disconnected;
    _eventCtrl.add(const Disconnected());
  }

  @override
  Future<SendResult> sendTo(
    String targetDeviceId,
    String channel,
    Map<String, dynamic> payload,
  ) async {
    final result = await _channelMgr.sendTo(targetDeviceId, channel, payload);
    return result.success
        ? SendResult.ok(statusCode: result.statusCode)
        : SendResult.fail(result.error ?? 'unknown');
  }

  @override
  Future<SendResult> sendRaw(
    String targetDeviceId,
    String channel,
    Uint8List data,
  ) async {
    final result = await _channelMgr.sendTo(targetDeviceId, channel, {'_raw': data});
    return result.success
        ? SendResult.ok(statusCode: result.statusCode)
        : SendResult.fail(result.error ?? 'unknown');
  }

  @override
  Stream<TransportMessage> watchChannel(String channel) {
    return _channelMgr.watchChannel(channel).map((msg) {
      return TransportMessage(
        sourceDeviceId: msg.sourceDeviceId,
        channel: msg.channel,
        payload: msg.payload,
        timestamp: msg.timestamp,
      );
    });
  }

  void dispose() {
    stop();
    _eventCtrl.close();
  }
}
