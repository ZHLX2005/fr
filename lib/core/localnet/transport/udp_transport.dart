import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'transport.dart';

/// UDP 多播数据报
class UdpDatagram {
  UdpDatagram({required this.data, required this.senderAddress});
  final List<int> data;
  final InternetAddress senderAddress;
}

/// UDP 多播传输
class UdpTransport extends Transport {
  UdpTransport({required super.config});

  RawDatagramSocket? _socket;
  StreamSubscription? _subscription;
  final _datagramController = StreamController<UdpDatagram>.broadcast();

  Stream<UdpDatagram> get datagrams => _datagramController.stream;

  bool _isRunning = false;
  @override
  bool get isRunning => _isRunning;

  @override
  Future<void> start() async {
    if (_isRunning) return;
    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        config.multicastPort,
        reuseAddress: true,
      );
      _socket!.joinMulticast(InternetAddress(config.multicastAddress));

      _subscription = _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _socket!.receive();
          if (dg != null) {
            _datagramController.add(
              UdpDatagram(data: dg.data, senderAddress: dg.address),
            );
          }
        }
      });

      _isRunning = true;
    } catch (e) {
      rethrow;
    }
  }

  /// 发送多播数据
  void send(String deviceId, int port, [List<String>? extras]) {
    if (_socket == null) {
      throw StateError('UdpTransport 未启动，无法发送');
    }
    final extrasStr =
        (extras == null || extras.isEmpty) ? '' : ',${extras.join(',')}';
    final message = '$deviceId,$port$extrasStr';
    final data = utf8.encode(message);
    _socket!.send(
      data,
      InternetAddress(config.multicastAddress),
      config.multicastPort,
    );
  }

  /// 发送任意 payload 到多播组（业务层通用广播通道）
  ///
  /// 与 [send] 不同：send 是 framework 内部设备发现用的（固定 deviceId,port,extras 格式），
  /// sendRaw 是业务层通用通道（如房间公告、聊天广播等）。
  void sendRaw(String payload) {
    if (_socket == null) {
      throw StateError('UdpTransport 未启动，无法发送');
    }
    final data = utf8.encode(payload);
    _socket!.send(
      data,
      InternetAddress(config.multicastAddress),
      config.multicastPort,
    );
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
    _isRunning = false;
  }
}
