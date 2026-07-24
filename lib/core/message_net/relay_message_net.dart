// lib/core/message_net/relay_message_net.dart
//
// Relay 模式实现 — 用 net_engine 引擎的 RelayTransport 替代原自实现 WebSocket
//
// 内部实现。业务层通过 [MessageNet.start] 获取 [MessageNet] 实例即可。
// LAN 实现保持不变，仅 Relay 路径换为引擎驱动。

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/core/net_engine/net_engine.dart' as fw;

import 'message_net.dart';

class RelayMessageNet implements MessageNet {
  RelayMessageNet._({required this.relayUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static Future<RelayMessageNet> create({
    required String relayUrl,
    http.Client? httpClient,
  }) async {
    return RelayMessageNet._(relayUrl: relayUrl, httpClient: httpClient);
  }

  final String relayUrl;
  final http.Client _http;

  fw.RelayTransport? _transport;
  StreamSubscription<fw.RemoteEvent>? _sub;
  bool _disposed = false;

  final StreamController<LogEntry> _anyCtrl =
      StreamController<LogEntry>.broadcast();
  final Map<String, StreamController<LogEntry>> _topicCtrls = {};
  final List<LogEntry> _queue = [];

  String? _roomCode;

  @override
  String? get roomCode => _roomCode;

  String get _roomsUrl => '$relayUrl/api/v1/relay/rooms';

  @override
  Future<String?> createRoom() async {
    final resp = await _http.post(
      Uri.parse(_roomsUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'deviceId': '', 'alias': 'host', 'maxPlayers': 100, 'canStartBeforeFull': true}),
    );
    if (resp.statusCode != 201) {
      throw StateError('createRoom failed: ${resp.statusCode}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    _roomCode = j['roomCode'] as String?;
    
    final t = await fw.RelayTransport.create(relayUrl: relayUrl, alias: 'host');
    _transport = t;
    _subscribe();
    return _roomCode;
  }

  @override
  Future<void> joinRoom(String code) async {
    final resp = await _http.post(
      Uri.parse('$_roomsUrl/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'deviceId': '', 'alias': 'guest', 'token': ''}),
    );
    if (resp.statusCode != 200) {
      throw StateError('joinRoom failed: ${resp.statusCode}');
    }
    final t = await fw.RelayTransport.create(relayUrl: relayUrl, alias: 'guest');
    _transport = t;
    _roomCode = code;
    _subscribe();
  }

  @override
  void leaveRoom() {
    _transport?.close();
    _transport = null;
    _roomCode = null;
  }

  void _subscribe() {
    _sub?.cancel();
    final t = _transport;
    final code = _roomCode;
    if (t == null || code == null) return;
    _sub = t.subscribe('room/$code/events').listen((ev) {
      final p = ev.payload;
      if (p['type'] != 'log') return;
      try {
        final raw = p['data'] as String? ?? '';
        final entry = LogEntry.decode(raw);
        _dispatch(entry);
      } catch (_) {}
    });
  }

  void _dispatch(LogEntry entry) {
    _anyCtrl.add(entry);
    final ctrl = _topicCtrls.putIfAbsent(entry.topic, () => StreamController<LogEntry>.broadcast());
    ctrl.add(entry);
  }

  @override
  void append(LogEntry entry) {
    _queue.add(entry);
    _flush();
  }

  Future<void> _flush() async {
    final t = _transport;
    final code = _roomCode;
    if (t == null || code == null) return;
    if (_queue.isEmpty) return;
    final items = List<LogEntry>.from(_queue);
    _queue.clear();
    for (final e in items) {
      try {
        await t.publish('room/$code/events', {
          'type': 'log',
          'data': e.encode(),
        });
      } catch (_) {
        _queue.add(e);
      }
    }
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
  Future<void> stop() async {
    if (_disposed) return;
    _disposed = true;
    await _sub?.cancel();
    for (final c in _topicCtrls.values) {
      await c.close();
    }
    _topicCtrls.clear();
    await _anyCtrl.close();
    await _transport?.close();
    _http.close();
  }
}
