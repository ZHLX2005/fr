import 'dart:async';
import 'dart:convert';

import '../io/udp_socket.dart';
import '../transport.dart';
import '../transport_event.dart';

/// LAN 传输实现 — UDP 多播
class LanTransport extends Transport {
  LanTransport._({
    required String multicastAddress,
    required int multicastPort,
  }) : _multicastAddress = multicastAddress,
       _multicastPort = multicastPort {
    // ignore: unused_field
  }

  /// 创建 LAN 传输
  static Future<LanTransport> create({
    String multicastAddress = '239.255.255.255',
    int multicastPort = 5678,
  }) async {
    final t = LanTransport._(
      multicastAddress: multicastAddress,
      multicastPort: multicastPort,
    );
    await t._socket.bind(multicastAddress: multicastAddress, port: multicastPort);
    t._socket.datagrams.listen(t._onDatagram);
    t._started = true;
    return t;
  }

  // ignore: unused_field
  final String _multicastAddress;
  // ignore: unused_field
  final int _multicastPort;
  final UdpMulticastSocket _socket = UdpMulticastSocket();

  final String _nodeId = DateTime.now().microsecondsSinceEpoch.toString();
  final StreamController<TransportEvent> _eventCtrl =
      StreamController<TransportEvent>.broadcast();
  final Map<String, DataLog> _scopes = {};
  final Map<String, StreamController<DataLog>> _scopeCtrls = {};
  final Set<String> _active = {};

  bool _started = false;

  @override
  String get myNodeId => _nodeId;

  @override
  Stream<TransportEvent> get events => _eventCtrl.stream;

  @override
  Set<String> get activeScopes => Set.unmodifiable(_active);

  @override
  DataLog? getScope(String scope) => _scopes[scope];

  @override
  Stream<DataLog> watchScope(String scope) {
    return _scopeCtrls
        .putIfAbsent(scope, () => StreamController<DataLog>.broadcast())
        .stream;
  }

  @override
  Future<void> joinScope(String scope) async {
    if (_active.contains(scope)) return;
    _active.add(scope);
    _scopes[scope] = DataLog(scope: scope, fromNodeId: _nodeId);
    // 广播心跳让对端知道我在这个 scope（用 topic 标记）
    await _broadcast({
      'type': 'scope-join',
      'scope': scope,
      'from': _nodeId,
    });
  }

  @override
  void leaveScope(String scope) {
    _active.remove(scope);
    _scopes.remove(scope);
  }

  @override
  void emit(TransportEvent event) {
    _eventCtrl.add(event);
  }

  @override
  Future<void> broadcastScope(String scope) async {
    final log = _scopes[scope];
    if (log == null) return;
    await _broadcast({
      'type': 'scope-update',
      'scope': scope,
      'state': log.state,
      'from': _nodeId,
    });
  }

  @override
  Future<void> broadcastEvent(String topic, Map<String, dynamic> data) async {
    await _broadcast({
      'type': 'event',
      'topic': topic,
      'data': data,
      'from': _nodeId,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
    await _socket.close();
    await _eventCtrl.close();
    for (final c in _scopeCtrls.values) {
      await c.close();
    }
    _scopeCtrls.clear();
    for (final s in _scopes.values) {
      await s.dispose();
    }
    _scopes.clear();
  }

  // ============ 内部 ============

  Future<void> _broadcast(Map<String, dynamic> envelope) async {
    if (!_started) return;
    final wire = jsonEncode(envelope);
    await _socket.send(utf8.encode(wire));
  }

  void _onDatagram(UdpDatagram dg) {
    try {
      final text = utf8.decode(dg.data, allowMalformed: true);
      final env = jsonDecode(text) as Map<String, dynamic>;
      _dispatch(env);
    } catch (_) {
      // 忽略非法包
    }
  }

  void _dispatch(Map<String, dynamic> env) {
    final type = env['type'] as String? ?? '';
    final from = env['from'] as String?;
    if (from == _nodeId) return; // 忽略自己

    switch (type) {
      case 'event':
        // 通用事件：业务层订阅 transport.events
        final topic = env['topic'] as String? ?? '';
        final data = (env['data'] as Map?)?.cast<String, dynamic>() ?? const {};
        final ts = DateTime.tryParse(env['ts'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        _eventCtrl.add(TransportEvent(topic: topic, data: data, timestamp: ts));
        break;

      case 'scope-update':
        // scope 状态更新
        final scope = env['scope'] as String?;
        if (scope == null) return;
        final log = DataLog.fromJson({
          'scope': scope,
          'state': (env['state'] as Map?)?.cast<String, dynamic>() ?? const {},
          'from': from,
        });
        final local = _scopes.putIfAbsent(
          scope,
          () => DataLog(scope: scope, fromNodeId: from ?? ''),
        );
        local.applyRemote(log);
        _scopeCtrls[scope]?.add(local);
        break;

      case 'scope-join':
        // 有人加入 scope — 触发本地事件供业务层观察
        final scope = env['scope'] as String?;
        if (scope == null) return;
        _eventCtrl.add(TransportEvent(
          topic: 'peer-joined-scope',
          data: {'scope': scope, 'from': from},
          timestamp: DateTime.now(),
        ));
        break;
    }
  }
}