import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../transport.dart';
import '../transport_event.dart';

/// Relay 传输实现 — HTTP 房间 + WebSocket
class RelayTransport extends Transport {
  RelayTransport._({
    required this.relayUrl,
    required String alias,
    http.Client? httpClient,
  })  : _alias = alias,
        _http = httpClient ?? http.Client();

  /// 创建 Relay 传输（仅初始化 http client，连接在 [createRoom]/[joinRoom] 后建立）
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

  final String _nodeId = DateTime.now().microsecondsSinceEpoch.toString();
  final StreamController<TransportEvent> _eventCtrl =
      StreamController<TransportEvent>.broadcast();
  final Map<String, DataLog> _scopes = {};
  final Map<String, StreamController<DataLog>> _scopeCtrls = {};
  final Set<String> _active = {};

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  bool _disposed = false;

  // ignore: unused_field
  String? _roomCode;

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
    await _send({'type': 'scope-join', 'scope': scope, 'from': _nodeId});
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
    await _send({
      'type': 'scope-update',
      'scope': scope,
      'state': log.state,
      'from': _nodeId,
    });
  }

  @override
  Future<void> broadcastEvent(String topic, Map<String, dynamic> data) async {
    await _send({
      'type': 'event',
      'topic': topic,
      'data': data,
      'from': _nodeId,
      'ts': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> start() async {
    // Relay 模式无显式 start；连接在 createRoom/joinRoom 后建立
  }

  /// 创建房间（认证步骤 — Relay 专用）
  Future<String> createRoom() async {
    final resp = await _http.post(
      Uri.parse('$relayUrl/api/v1/relay/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'alias': _alias, 'deviceId': _nodeId}),
    );
    if (resp.statusCode != 201) {
      throw _RelayException('创建房间失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final code = json['roomCode'] as String;
    final wsUrl = json['wsUrl'] as String;
    _roomCode = code;
    await _connect(wsUrl);
    return code;
  }

  /// 加入房间（认证步骤 — Relay 专用）
  Future<void> joinRoom(String code) async {
    final resp = await _http.post(
      Uri.parse('$relayUrl/api/v1/relay/rooms/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'deviceId': _nodeId, 'alias': _alias}),
    );
    if (resp.statusCode == 404) {
      throw _RelayNotFoundException('房间 $code 不存在');
    }
    if (resp.statusCode != 200) {
      throw _RelayException('加入房间失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final wsUrl = json['wsUrl'] as String?;
    if (wsUrl == null || wsUrl.isEmpty) {
      throw _RelayException('加入房间响应缺少 wsUrl');
    }
    _roomCode = code;
    await _connect(wsUrl);
  }

  Future<void> _connect(String wsUrl) async {
    final ws = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = ws;

    // 发送 identify 帧（relay 服务器要求）— 用 TransportFrame 格式
    final identifyPayload = utf8.encode(jsonEncode({'alias': _alias}));
    ws.sink.add(jsonEncode({
      'channelName': 'identify',
      'sourceDeviceId': _nodeId,
      'payload': base64Encode(identifyPayload),
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
      // 跳过 identify / room_event 等系统帧，只处理 scope 帧
      final ch = env['channelName'] as String?;
      if (ch != null && ch != 'scope' && ch != 'scope-update') return;
      _dispatch(env);
    } catch (_) {}
  }

  void _dispatch(Map<String, dynamic> env) {
    final type = env['type'] as String? ?? '';
    final from = env['from'] as String?;
    if (from == _nodeId) return;

    switch (type) {
      case 'event':
        final topic = env['topic'] as String? ?? '';
        final data = (env['data'] as Map?)?.cast<String, dynamic>() ?? const {};
        final ts = DateTime.tryParse(env['ts'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        _eventCtrl.add(TransportEvent(topic: topic, data: data, timestamp: ts));
        break;

      case 'scope-update':
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

  Future<void> _send(Map<String, dynamic> envelope) async {
    final ws = _ws;
    if (ws == null) return;
    // 加 relay 服务器要求的字段（channelName + sourceDeviceId）
    envelope.putIfAbsent('channelName', () => 'scope');
    envelope.putIfAbsent('sourceDeviceId', () => _nodeId);
    ws.sink.add(jsonEncode(envelope));
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    _disposed = true;
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
    _http.close();
    _roomCode = null;
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