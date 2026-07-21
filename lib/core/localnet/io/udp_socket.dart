import 'dart:async';
import 'dart:io';

/// UDP 多播 socket 封装
class UdpMulticastSocket {
  RawDatagramSocket? _socket;
  final StreamController<UdpDatagram> _ctrl =
      StreamController<UdpDatagram>.broadcast();
  StreamSubscription<RawSocketEvent>? _sub;

  /// 多播数据报流
  Stream<UdpDatagram> get datagrams => _ctrl.stream;

  /// 绑定多播组
  Future<void> bind({
    required String multicastAddress,
    required int port,
  }) async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    _socket!.joinMulticast(InternetAddress(multicastAddress));
    _sub = _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket?.receive();
        if (dg != null) {
          _ctrl.add(UdpDatagram(data: dg.data, senderAddress: dg.address));
        }
      }
    });
  }

  /// 发送多播
  Future<void> send(List<int> data) async {
    final s = _socket;
    if (s == null) return;
    s.send(data, InternetAddress('239.255.255.255'), 0);  // 用默认 addr/port 时由 bind 决定
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    await _ctrl.close();
  }
}

class UdpDatagram {
  UdpDatagram({required this.data, required this.senderAddress});
  final List<int> data;
  final InternetAddress senderAddress;
}