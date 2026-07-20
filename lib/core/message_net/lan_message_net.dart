import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'message_net.dart';

/// LAN 模式实现 — UDP 多播（独立实现，不复用任何已有代码）
///
/// 内部实现。业务层通过 [MessageNet.start] 获取 [MessageNet] 实例即可。
class LanMessageNet implements MessageNet {
  LanMessageNet._({
    required this.multicastPort,
    required this.multicastAddress,
  });

  /// 工厂：绑定 UDP socket
  static Future<LanMessageNet> create({
    required int multicastPort,
    required String multicastAddress,
  }) async {
    final net = LanMessageNet._(
      multicastPort: multicastPort,
      multicastAddress: multicastAddress,
    );
    await net._bind();
    return net;
  }

  final int multicastPort;
  final String multicastAddress;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;

  final StreamController<LogEntry> _anyCtrl =
      StreamController<LogEntry>.broadcast();
  final Map<String, StreamController<LogEntry>> _topicCtrls = {};
  final List<LogEntry> _queue = [];

  @override
  String? get roomCode => null;

  Future<void> _bind() async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      multicastPort,
      reuseAddress: true,
    );
    _socket!.joinMulticast(InternetAddress(multicastAddress));

    _sub = _socket!.listen(_onEvent);
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    final text = utf8.decode(dg.data, allowMalformed: true);
    try {
      final entry = LogEntry.decode(text);
      _dispatch(entry);
    } catch (_) {
      // 忽略非法包
    }
  }

  void _dispatch(LogEntry entry) {
    _anyCtrl.add(entry);
    final ctrl = _topicCtrls[entry.topic];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(entry);
    }
  }

  @override
  void append(LogEntry entry) {
    _queue.add(entry);
    // UDP 多播是"无连接"模式：直接发
    _socket?.send(
      utf8.encode(entry.encode()),
      InternetAddress(multicastAddress),
      multicastPort,
    );
  }

  @override
  Stream<LogEntry> watch(String topic) {
    return _topicCtrls
        .putIfAbsent(topic, () => StreamController<LogEntry>.broadcast())
        .stream;
  }

  @override
  Stream<LogEntry> get onAny => _anyCtrl.stream;

  @override
  Future<String?> createRoom() async => null;

  @override
  Future<void> joinRoom(String code) async {
    // LAN 模式：无需操作（多播自动发现）
  }

  @override
  void leaveRoom() {
    // LAN 模式：无需操作
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    await _anyCtrl.close();
    for (final c in _topicCtrls.values) {
      await c.close();
    }
    _topicCtrls.clear();
    _queue.clear();
  }
}