import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../transport/transport_frame.dart';
import '../transport/ws_transport.dart';
import '../transport_channel/relay_channel.dart';
import 'transport_service.dart';

/// Relay 传输服务实现 — 基于 RelayChannel (WS 帧)
class RelayTransportService implements TransportService {
  RelayTransportService({
    required String myDeviceId,
    WsTransport? wsTransport,
    RelayChannel? relayChannel,
  })  : _myDeviceId = myDeviceId,
        _ws = wsTransport,
        _channel = relayChannel;

  final String _myDeviceId;
  // ignore: unused_field
  WsTransport? _ws;
  RelayChannel? _channel;

  final StreamController<TransportEvent> _eventCtrl =
      StreamController<TransportEvent>.broadcast();
  final Map<String, List<StreamController<TransportMessage>>> _watchers = {};
  StreamSubscription<TransportFrame>? _wsFrameSub;
  bool _started = false;

  @override
  TransportConnectionState connectionState =
      TransportConnectionState.disconnected;

  @override
  String get myDeviceId => _myDeviceId;

  @override
  Stream<TransportEvent> get events => _eventCtrl.stream;

  /// 连接 — 传入已 open 的 WsTransport + RelayChannel
  void connect(WsTransport ws, RelayChannel channel) {
    _ws = ws;
    _channel = channel;
    _started = true;
    connectionState = TransportConnectionState.connected;
    _eventCtrl.add(const Connected());

    // 直接订阅 WsTransport 的帧流（不依赖 RelayChannel.frames）
    _wsFrameSub = ws.frames.listen(
      (frame) {
        final ctx = _watchers[frame.channelName];
        if (ctx == null) return;
        TransportMessage msg;
        try {
          final text = utf8.decode(frame.payload);
          final json = jsonDecode(text) as Map<String, dynamic>;
          msg = TransportMessage(
            sourceDeviceId: frame.sourceDeviceId,
            channel: frame.channelName,
            payload: json,
            timestamp: frame.timestamp,
          );
        } catch (_) {
          msg = TransportMessage(
            sourceDeviceId: frame.sourceDeviceId,
            channel: frame.channelName,
            payload: {},
            timestamp: frame.timestamp,
          );
        }
        for (final c in ctx) {
          c.add(msg);
        }
      },
      onError: (e) {
        _eventCtrl.add(TransportError(e));
      },
      onDone: () {
        connectionState = TransportConnectionState.disconnected;
        _eventCtrl.add(const Disconnected());
      },
    );
  }

  void disconnect() {
    _wsFrameSub?.cancel();
    _wsFrameSub = null;
    _started = false;
    connectionState = TransportConnectionState.disconnected;
    _eventCtrl.add(const Disconnected());
  }

  @override
  Future<SendResult> sendTo(
    String targetDeviceId,
    String channel,
    Map<String, dynamic> payload,
  ) async {
    final ch = _channel;
    if (ch == null) return SendResult.fail('未连接');
    try {
      await ch.send(channel, Uint8List.fromList(utf8.encode(jsonEncode(payload))));
      return SendResult.ok();
    } catch (e) {
      return SendResult.fail('$e');
    }
  }

  @override
  Future<SendResult> sendRaw(
    String targetDeviceId,
    String channel,
    Uint8List data,
  ) async {
    final ch = _channel;
    if (ch == null) return SendResult.fail('未连接');
    try {
      await ch.send(channel, data);
      return SendResult.ok();
    } catch (e) {
      return SendResult.fail('$e');
    }
  }

  @override
  Stream<TransportMessage> watchChannel(String channel) {
    final ctrl = StreamController<TransportMessage>.broadcast();
    _watchers.putIfAbsent(channel, () => []).add(ctrl);
    return ctrl.stream;
  }

  void dispose() {
    disconnect();
    for (final list in _watchers.values) {
      for (final c in list) {
        c.close();
      }
    }
    _watchers.clear();
    _eventCtrl.close();
  }
}
