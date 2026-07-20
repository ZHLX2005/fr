import 'dart:async';
import 'dart:typed_data';

import '../transport/transport_frame.dart';
import '../transport/ws_transport.dart';
import 'transport_channel.dart';

/// Relay 后端的 TransportChannel — 通过 WsTransport 路由 frame 到对应虚拟通道
class RelayChannel implements TransportChannel {
  RelayChannel({required WsTransport ws, required this.myDeviceId}) : _ws = ws {
    _sub = _ws.frames.listen(_onFrame);
  }

  final WsTransport _ws;
  final String myDeviceId;
  final Map<String, StreamController<TransportFrame>> _watchers = {};
  StreamSubscription<TransportFrame>? _sub;

  @override
  Future<void> open({required String channelName, required String remoteDeviceId}) async {
    _watchers.putIfAbsent(channelName, () => StreamController<TransportFrame>.broadcast());
  }

  @override
  Future<SendResult> send(String channelName, Uint8List data) async {
    await _ws.send(TransportFrame(
      channelName: channelName,
      sourceDeviceId: myDeviceId,
      payload: data,
      timestamp: DateTime.now(),
    ));
    return SendResult.ok();
  }

  @override
  Stream<TransportFrame> watch(String channelName) {
    return _watchers
        .putIfAbsent(channelName, () => StreamController<TransportFrame>.broadcast())
        .stream;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    for (final c in _watchers.values) {
      await c.close();
    }
    _watchers.clear();
  }

  void _onFrame(TransportFrame frame) {
    _watchers[frame.channelName]?.add(frame);
  }
}