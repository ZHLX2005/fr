import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../transport.dart';

/// Relay 传输实现 — WS pub/sub + v1 scope 兼容
///
/// v1 scope API 内部用 topic 实现：
/// - `joinScope('room/X')` → `subscribe('room/X/events')`
/// - `broadcastScope('room/X')` → `publish('room/X/events', {state})`
/// - `watchScope('room/X')` → 转换为 RemoteEvent 流 + 内部 DataLog mirror
class RelayTransport implements Transport {
  RelayTransport._({
    required this.relayUrl,
    required String alias,
    http.Client? httpClient,
  })  : _alias = alias,
        _http = httpClient ?? http.Client();

  static Future<RelayTransport> create({
    required String relayUrl,
    String alias = 'Flutter Device',
    http.Client? httpClient,
  }) async {
    return RelayTransport._(
      relayUrl: relayUrl,
      alias: alias,
      httpClient: httpClient,
    );
  }

  final String relayUrl;
  final String _alias;
  final http.Client _http;

  final int _createdAt = DateTime.now().microsecondsSinceEpoch;
  final String _nodeId = '${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch % 1000}';
  RoomInfo? _roomInfo;
  bool _disposed = false;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;

  // v2 pub/sub state
  final Map<String, StreamController<RemoteEvent>> _subCtrl = {};
  final Set<String> _subscribedTopics = {};

  // v1 scope compat state
  final StreamController<TransportEvent> _eventCtrl =
      StreamController<TransportEvent>.broadcast();
  final Map<String, DataLog> _scopes = {};
  final Map<String, StreamController<DataLog>> _scopeCtrls = {};
  final Set<String> _active = {};
  NodeRole _role = NodeRole.unknown;
  NodeRole _peerRole = NodeRole.unknown;
  String? _peerNodeId;

  @override
  String get myNodeId => _nodeId;

  @override
  int get myCreatedAt => _createdAt;

  @override
  RoomInfo? get roomInfo => _roomInfo;

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
  bool get isConnected => _ws != null;

  // ---------------- v2 pub/sub ----------------

  @override
  Future<void> connect() async {}

  @override
  Future<void> close() async => stop();

  @override
  Stream<RemoteEvent> subscribe(String topic) {
    final ctrl = _subCtrl.putIfAbsent(
      topic,
      () => StreamController<RemoteEvent>.broadcast(),
    );
    if (_subscribedTopics.add(topic)) {
      _ws?.sink.add(jsonEncode({
        'channelName': topic,
        'sourceDeviceId': _nodeId,
        'op': 'subscribe',
      }));
    }
    return ctrl.stream;
  }

  @override
  Future<void> unsubscribe(String topic) async {
    final ctrl = _subCtrl.remove(topic);
    if (ctrl != null) await ctrl.close();
    if (_subscribedTopics.remove(topic)) {
      _ws?.sink.add(jsonEncode({
        'channelName': topic,
        'sourceDeviceId': _nodeId,
        'op': 'unsubscribe',
      }));
    }
  }

  @override
  Future<void> publish(String topic, Map<String, dynamic> payload) async {
    final ws = _ws;
    if (ws == null) throw StateError('RelayTransport.publish before connect');
    ws.sink.add(jsonEncode({
      'channelName': topic,
      'sourceDeviceId': _nodeId,
      'payload': jsonEncode(payload),
      'timestamp': DateTime.now().toIso8601String(),
    }));
  }

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
    // v2: subscribe to equivalent topic.
    subscribe(scope.startsWith('room/') ? '$scope/events' : scope)
        .listen(null); // passive subscribe; events delivered via _subCtrl
    await _send({'type': 'scope-join', 'scope': scope, 'from': _nodeId});
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
    await _send({
      'type': 'scope-update',
      'scope': scope,
      'state': log.state,
      'from': _nodeId,
    });
  }

  @override
  Future<void> sendEvent(
      String scope, String topic, Map<String, dynamic> data) async {
    if (!_active.contains(scope)) return;
    await _send({
      'type': 'event',
      'scope': scope,
      'topic': topic,
      'data': data,
      'from': _nodeId,
    });
  }

  @override
  void emit(TransportEvent event) => _eventCtrl.add(event);

  @override
  Future<void> start() async {}

  // ---------------- 房间 (v2) ----------------

  @override
  Future<RoomInfo> createRoom(RoomConfig config) async {
    final info = await _createRoomImpl(config);
    return info;
  }

  /// v1-compat: returns just the room code (used by RelayDiscovery widget).
  Future<String> createRoomCompat() async {
    final info = await _createRoomImpl(RoomConfig());
    return info.code;
  }

  Future<RoomInfo> _createRoomImpl(RoomConfig config) async {
    final resp = await _http.post(
      Uri.parse('$relayUrl/api/v1/relay/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'alias': _alias,
        'deviceId': _nodeId,
        'maxPlayers': config.maxPlayers,
        'schema': config.schema,
        'canStartBeforeFull': config.canStartBeforeFull,
        'autoStartThreshold': config.autoStartThreshold,
      }),
    );
    if (resp.statusCode != 201) {
      throw _RelayException('创建房间失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final wsUrl = json['wsUrl'] as String;
    final token = json['token'] as String? ?? '';
    await _connect(wsUrl);
    final info = RoomInfo(
      code: json['roomCode'] as String,
      hostNodeId: _nodeId,
      maxPlayers: config.maxPlayers,
      token: token,
      config: config,
    );
    _roomInfo = info;
    return info;
  }

  @override
  Future<void> joinRoom(String code, String token) async {
    await _joinRoomImpl(code, token);
  }

  /// v1-compat: 1-arg signature (no token, for RelayDiscovery widget).
  Future<void> joinRoomCompat(String code) async {
    await _joinRoomImpl(code, '');
  }

  Future<void> _joinRoomImpl(String code, String token) async {
    final resp = await _http.post(
      Uri.parse('$relayUrl/api/v1/relay/rooms/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'deviceId': _nodeId, 'alias': _alias, 'token': token}),
    );
    if (resp.statusCode == 404) {
      throw _RelayNotFoundException('房间 $code 不存在');
    }
    if (resp.statusCode == 403) {
      throw _RelayException('token 无效');
    }
    if (resp.statusCode == 409) {
      throw _RelayException('房间已满');
    }
    if (resp.statusCode != 200) {
      throw _RelayException('加入房间失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final wsUrl = json['wsUrl'] as String?;
    if (wsUrl == null || wsUrl.isEmpty) {
      throw _RelayException('加入房间响应缺少 wsUrl');
    }
    await _connect(wsUrl);
    final maxPlayers = (json['maxPlayers'] as int?) ?? 0;
    _roomInfo = RoomInfo(code: code, hostNodeId: '', maxPlayers: maxPlayers, token: '');
  }

  @override
  Future<void> leaveRoom(String code) async {
    await unsubscribe('room/$code/events');
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _disposed = true;
    for (final ctrl in _subCtrl.values) {
      await ctrl.close();
    }
    _subCtrl.clear();
    _subscribedTopics.clear();
    for (final c in _scopeCtrls.values) {
      await c.close();
    }
    _scopeCtrls.clear();
    for (final s in _scopes.values) {
      await s.dispose();
    }
    _scopes.clear();
    await _eventCtrl.close();
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
    _http.close();
  }

  // ---------------- 内部 ----------------

  Future<void> _connect(String wsUrl) async {
    final ws = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = ws;

    ws.sink.add(jsonEncode({
      'channelName': 'identify',
      'sourceDeviceId': _nodeId,
      'payload': base64Encode(utf8.encode(jsonEncode({'alias': _alias}))),
      'timestamp': DateTime.now().toIso8601String(),
    }));

    _wsSub = ws.stream.listen(
      _onFrame,
      onError: (_) {},
      onDone: () {},
    );
  }

  void _onFrame(dynamic data) {
    if (data is! String) return;
    try {
      final env = jsonDecode(data) as Map<String, dynamic>;
      final ch = env['channelName'] as String?;
      if (ch == null || ch == 'identify') return;
      // 路由到 v2 订阅者
      final sub = _subCtrl[ch];
      if (sub != null && !sub.isClosed) {
        Map<String, dynamic> payload = const {};
        final raw = env['payload'];
        if (raw is String && raw.isNotEmpty) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) payload = decoded;
          } catch (_) {}
        }
        sub.add(RemoteEvent(
          topic: ch,
          fromNodeId: env['sourceDeviceId'] as String? ?? '',
          payload: payload,
        ));
      }
      // v1 scope 兼容：scope / scope-update / event 类型
      _dispatchV1(env, ch);
    } catch (_) {}
  }

  void _dispatchV1(Map<String, dynamic> env, String ch) {
    final from = env['sourceDeviceId'] as String?;
    if (from == _nodeId) return;
    // v1 payload 字段映射
    final type = ch == 'scope' || ch == 'scope-update' ? ch : null;
    if (type == 'scope-update') {
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
    } else if (type == 'scope') {
      // scope-join event
      final scope = env['scope'] as String?;
      if (scope == null) return;
      _eventCtrl.add(TransportEvent(
        topic: 'peer-joined-scope',
        data: {'scope': scope, 'from': from},
        timestamp: DateTime.now(),
      ));
    } else if (ch.startsWith('event:')) {
      // 旧 event 格式（如果有遗留）
    }
  }

  Future<void> _send(Map<String, dynamic> envelope) async {
    final ws = _ws;
    if (ws == null) return;
    envelope.putIfAbsent('channelName', () => 'scope');
    envelope.putIfAbsent('sourceDeviceId', () => _nodeId);
    ws.sink.add(jsonEncode(envelope));
  }
}

class _RelayException implements Exception {
  _RelayException(this.message);
  final String message;
  @override
  String toString() => message;
}

class _RelayNotFoundException extends _RelayException {
  _RelayNotFoundException(super.message);
}