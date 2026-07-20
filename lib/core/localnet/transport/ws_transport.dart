import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport_frame.dart';

/// WebSocket 多路复用传输 — 单连接承载多个虚拟通道
///
/// 出站 frame 直接发 JSON 文本帧；
/// 入站 frame 解析后通过 frames 流广播（业务层按 channelName 过滤）。
class WsTransport {
  WsTransport({
    required WebSocketChannel channel,
    required this.myDeviceId,
  }) : _channel = channel {
    _sub = _channel.stream.listen(
      _onIncoming,
      onError: _onError,
      onDone: _onDone,
    );
  }

  final WebSocketChannel _channel;
  final String myDeviceId;
  final StreamController<TransportFrame> _framesCtrl =
      StreamController<TransportFrame>.broadcast();
  final StreamController<Object> _errorsCtrl =
      StreamController<Object>.broadcast();
  StreamSubscription? _sub;
  bool _closed = false;

  /// 入站帧流
  Stream<TransportFrame> get frames => _framesCtrl.stream;

  /// 错误流（断连 / 解析失败）
  Stream<Object> get errors => _errorsCtrl.stream;

  /// 发送一帧
  Future<void> send(TransportFrame frame) async {
    if (_closed) return;
    _channel.sink.add(jsonEncode(frame.toJson()));
  }

  /// 关闭连接
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    await _channel.sink.close();
    await _framesCtrl.close();
    await _errorsCtrl.close();
  }

  void _onIncoming(dynamic data) {
    if (data is! String) return;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      _framesCtrl.add(TransportFrame.fromJson(json));
    } catch (e) {
      _errorsCtrl.add(e);
    }
  }

  void _onError(Object e) {
    _errorsCtrl.add(e);
  }

  void _onDone() {
    _errorsCtrl.add('ws_done');
  }
}