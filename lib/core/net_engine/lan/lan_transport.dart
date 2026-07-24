import 'dart:async';
import 'dart:convert';

import '../io/udp_socket.dart';
import '../transport.dart';

/// LAN 传输实现 — UDP 发现 + HTTP pub/sub（双 API 兼容）
///
/// v1 scope API 内部用 topic + 内存 DataLog 镜像实现
/// v2 pub/sub API 走 HTTP POST（直接投递到对端 HTTP server）
class LanTransport implements Transport {
  LanTransport._({
    required String multicastAddress,
    required int multicastPort,
    required int httpPort,
    required String alias,
  })  : _multicastAddress = multicastAddress,
        _multicastPort = multicastPort,
        _httpPort = httpPort,
        _alias = alias;

  static Future<LanTransport> create({
    String multicastAddress = '239.255.255.255',
    int multicastPort = 5678,
    int httpPort = 53318,
    String alias = 'Flutter Device',
  }) async {
    final t = LanTransport._(
      multicastAddress: multicastAddress,
      multicastPort: multicastPort,
      httpPort: httpPort,
      alias: alias,
    );
    await t._socket.bind(multicastAddress: multicastAddress, port: multicastPort);
    t._socket.datagrams.listen(t._onDatagram);
    return t;
  }

  // ignore: unused_field
  final String _multicastAddress;
  // ignore: unused_field
  final int _multicastPort;
  final int _httpPort;
  final String _alias;
  final UdpMulticastSocket _socket = UdpMulticastSocket();

  final int _createdAt = DateTime.now().microsecondsSinceEpoch;
  final String _nodeId = '${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch % 1000}';

  // 已知 peer：nodeId -> (ip, httpPort)
  final Map<String, _PeerEndpoint> _peers = {};

  // v2 pub/sub
  final Map<String, StreamController<RemoteEvent>> _subCtrl = {};

  // v1 scope 兼容
  final StreamController<TransportEvent> _eventCtrl =
      StreamController<TransportEvent>.broadcast();
  final Map<String, DataLog> _scopes = {};
  final Map<String, StreamController<DataLog>> _scopeCtrls = {};
  final Set<String> _active = {};
  NodeRole _role = NodeRole.unknown;
  NodeRole _peerRole = NodeRole.unknown;
  String? _peerNodeId;

  // HTTP publish client (set by LanDiscovery widget after starting HTTP server)
  _HttpPublishClient? _publishClient;

  @override
  String get myNodeId => _nodeId;

  @override
  int get myCreatedAt => _createdAt;

  @override
  RoomInfo? get roomInfo => null;

  @override
  NodeRole get myRole => _role;

  @override
  void setRole(NodeRole role) => _role = role;

  @override
  String? get peerNodeId => _peerNodeId;

  @override
  void setPeerNodeId(String? nodeId) => _peerNodeId = nodeId;

  @override
  NodeRole get peerRole => _peerRole;

  @override
  void setPeerRole(NodeRole role) => _peerRole = role;

  @override
  bool get isConnected => _publishClient != null;

  // ---------------- v2 pub/sub ----------------

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async => stop();

  @override
  Stream<RemoteEvent> subscribe(String topic) {
    return _subCtrl
        .putIfAbsent(topic, () => StreamController<RemoteEvent>.broadcast())
        .stream;
  }

  @override
  Future<void> unsubscribe(String topic) async {
    final ctrl = _subCtrl.remove(topic);
    if (ctrl != null) await ctrl.close();
  }

  @override
  Future<void> publish(String topic, Map<String, dynamic> payload) async {
    final client = _publishClient;
    if (client == null) {
      throw StateError('LanTransport.publish before setPublishClient');
    }
    for (final peer in _peers.values) {
      unawaited(client.post(peer.ip, peer.httpPort, topic, payload));
    }
  }

  /// Incoming HTTP-published event from a peer (called by LanDiscovery).
  void deliverRemoteEvent(RemoteEvent event) {
    final ctrl = _subCtrl[event.topic];
    if (ctrl == null || ctrl.isClosed) return;
    ctrl.add(event);
  }

  void setPublishClient(_HttpPublishClient client) {
    _publishClient = client;
  }

  /// Currently known peer endpoints (read-only view for the widget).
  Map<String, _PeerEndpoint> get knownPeers => Map.unmodifiable(_peers);

  // ---------------- v1 scope compat ----------------

  @override
  Stream<TransportEvent> get events => _eventCtrl.stream;

  @override
  Set<String> get activeScopes => Set.unmodifiable(_active);

  @override
  Future<void> joinScope(String scope) async {
    if (_active.contains(scope)) return;
    _active.add(scope);
    _scopes.putIfAbsent(scope, () => DataLog(scope: scope, fromNodeId: _nodeId));
  }

  @override
  void leaveScope(String scope) {
    _active.remove(scope);
    _scopes.remove(scope);
  }

  @override
  Stream<DataLog> watchScope(String scope) {
    return _scopeCtrls
        .putIfAbsent(scope, () => StreamController<DataLog>.broadcast())
        .stream;
  }

  @override
  DataLog? getScope(String scope) => _scopes[scope];

  @override
  Future<void> broadcastScope(String scope) async {
    final log = _scopes[scope];
    if (log == null) return;
    final env = {
      'type': 'scope-update',
      'scope': scope,
      'state': log.state,
      'from': _nodeId,
    };
    final wire = utf8.encode(jsonEncode(env));
    await _socket.send(wire);
  }

  @override
  Future<void> sendEvent(
      String scope, String topic, Map<String, dynamic> data) async {
    if (!_active.contains(scope)) return;
    final env = {
      'type': 'event',
      'scope': scope,
      'topic': topic,
      'data': data,
      'from': _nodeId,
    };
    final wire = utf8.encode(jsonEncode(env));
    await _socket.send(wire);
  }

  @override
  void emit(TransportEvent event) => _eventCtrl.add(event);

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    for (final ctrl in _subCtrl.values) {
      await ctrl.close();
    }
    _subCtrl.clear();
    for (final c in _scopeCtrls.values) {
      await c.close();
    }
    _scopeCtrls.clear();
    for (final s in _scopes.values) {
      await s.dispose();
    }
    _scopes.clear();
    await _eventCtrl.close();
    await _socket.close();
  }

  // ---------------- 房间 (v2) ----------------

  @override
  Future<RoomInfo> createRoom(RoomConfig config) async {
    throw UnsupportedError(
      'LanTransport.createRoom: rooms are created via LanDiscovery widget',
    );
  }

  @override
  Future<void> joinRoom(String code, String token) async {
    throw UnsupportedError(
      'LanTransport.joinRoom: rooms are joined via LanDiscovery widget',
    );
  }

  @override
  Future<void> leaveRoom(String code) async {
    await unsubscribe('room/$code/events');
  }

  // ---------------- UDP 发现 ----------------

  void _onDatagram(UdpDatagram dg) {
    try {
      final text = utf8.decode(dg.data, allowMalformed: true);
      final env = jsonDecode(text) as Map<String, dynamic>;
      final from = env['from'] as String?;
      if (from == null || from == _nodeId) return;
      final alias = env['alias'] as String? ?? from.substring(0, 6);
      // v1 scope-join UDP 包
      if (env['type'] == 'scope-join') {
        _active.add(env['scope'] as String? ?? '');
        _eventCtrl.add(TransportEvent(
          topic: 'peer-joined-scope',
          data: {
            'scope': env['scope'],
            'from': from,
            'alias': alias,
            'ip': dg.senderAddress.address,
            'httpPort': env['httpPort'] as int? ?? 0,
            'createdAt': env['createdAt'] as int? ?? 0,
          },
          timestamp: DateTime.now(),
        ));
      }
      // v2 discovery 包 — 也触发 peer-joined-scope 事件
      if (env['type'] == 'discovery') {
        _peers[from] = _PeerEndpoint(
          ip: dg.senderAddress.address,
          httpPort: env['httpPort'] as int? ?? 0,
        );
        _eventCtrl.add(TransportEvent(
          topic: 'peer-joined-scope',
          data: {
            'scope': 'peers',
            'from': from,
            'alias': alias,
            'ip': dg.senderAddress.address,
            'httpPort': env['httpPort'] as int? ?? 0,
            'createdAt': env['createdAt'] as int? ?? 0,
          },
          timestamp: DateTime.now(),
        ));
      }
    } catch (_) {}
  }

  /// Broadcast v2 discovery presence. Called by LanDiscovery periodically.
  void broadcastDiscovery() {
    final env = {
      'type': 'discovery',
      'from': _nodeId,
      'alias': _alias,
      'httpPort': _httpPort,
      'createdAt': _createdAt,
    };
    final wire = utf8.encode(jsonEncode(env));
    _socket.send(wire);
  }

  /// Broadcast v1 scope-join (used by v1 compat path during migration).
  void broadcastScopeJoin(String scope) {
    final env = {
      'type': 'scope-join',
      'scope': scope,
      'from': _nodeId,
      'alias': _alias,
      'httpPort': _httpPort,
      'createdAt': _createdAt,
    };
    final wire = utf8.encode(jsonEncode(env));
    _socket.send(wire);
  }
}

class _PeerEndpoint {
  _PeerEndpoint({required this.ip, required this.httpPort});
  final String ip;
  final int httpPort;
}

abstract class _HttpPublishClient {
  Future<void> post(
      String ip, int port, String topic, Map<String, dynamic> payload);
}