import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class HistoryEntry {
  final String type;
  final Map<String, dynamic>? params;
  final String fromState;
  final String toState;
  final DateTime at;
  final int version;

  HistoryEntry({
    required this.type,
    this.params,
    required this.fromState,
    required this.toState,
    required this.at,
    required this.version,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        type: j['type'] as String,
        params: j['params'] as Map<String, dynamic>?,
        fromState: j['from_state'] as String,
        toState: j['to_state'] as String,
        at: DateTime.parse(j['at'] as String),
        version: j['version'] as int,
      );
}

class Snapshot {
  final String roomCode;
  final String scriptHash;
  final String scriptSrc;
  final Map<String, dynamic> context;
  final String state;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<HistoryEntry> history;

  Snapshot({
    required this.roomCode,
    required this.scriptHash,
    required this.scriptSrc,
    required this.context,
    required this.state,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.history,
  });

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        roomCode: j['room_code'] as String,
        scriptHash: j['script_hash'] as String,
        scriptSrc: j['script_src'] as String,
        context: Map<String, dynamic>.from(j['context'] as Map),
        state: j['state'] as String,
        version: j['version'] as int,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
        history: (j['history'] as List)
            .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class RoomHandle {
  final RelayV3Transport transport;
  final String code;
  final String wsUrl;
  Snapshot? latest;

  final _snapshots = StreamController<Snapshot>.broadcast();
  Stream<Snapshot> get snapshots => _snapshots.stream;

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connected = false;
  int _backoffMs = 500;

  RoomHandle({
    required this.transport,
    required this.code,
    required this.wsUrl,
    Snapshot? initial,
  }) {
    if (initial != null) {
      latest = initial;
      _snapshots.add(initial);
    }
  }

  Future<void> connect() async {
    if (_disposed) return;
    if (_connected) return; // Idempotent: lobby + chat page may both call.
    final uri = Uri.parse(wsUrl);
    try {
      _ws = WebSocketChannel.connect(uri);
      _wsSub = _ws!.stream.listen(
        (msg) {
          try {
            final m = jsonDecode(msg as String) as Map<String, dynamic>;
            if (m['type'] == 'snapshot') {
              final s = Snapshot.fromJson(m['data'] as Map<String, dynamic>);
              latest = s;
              _snapshots.add(s);
            }
          } catch (_) {
            // Ignore malformed messages.
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
      _connected = true;
      _backoffMs = 500;
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _connected = false; // Allow reconnect to pass the guard.
    _wsSub?.cancel();
    _wsSub = null;
    _ws = null;
    final wait = _backoffMs;
    _backoffMs = (_backoffMs * 2).clamp(500, 30000);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: wait), connect);
  }

  Future<Snapshot> applyAction({
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    String? sourceDeviceId,
  }) async {
    final snap = await transport._applyAction(
      code: code,
      type: type,
      params: params,
      expectVersion: expectVersion,
      sourceDeviceId: sourceDeviceId ?? transport.deviceId,
    );
    latest = snap;
    _snapshots.add(snap);
    return snap;
  }

  Future<void> leave() async {
    try {
      await transport._leave(code: code, deviceId: transport.deviceId);
    } catch (_) {
      // Best-effort leave.
    }
    await dispose();
  }

  Future<void> dispose() async {
    if (_disposed) return; // Idempotent: leave() and page dispose may both call.
    _disposed = true;
    _connected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
    await _snapshots.close();
  }
}

class RelayV3Transport {
  final String relayUrl;
  final String alias;
  final String deviceId;
  final http.Client _http;

  RelayV3Transport({
    required this.relayUrl,
    required this.alias,
    required this.deviceId,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Uri _u(String path) => Uri.parse('$relayUrl$path');

  Future<RoomHandle> createRoom({
    required String script,
    required Map<String, dynamic> initialParams,
    int maxPlayers = 8,
  }) async {
    final resp = await _http.post(
      _u('/api/v3/relay/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'script': script,
        'initial_params': initialParams,
        'alias': alias,
        'device_id': deviceId,
        'max_players': maxPlayers,
      }),
    );
    if (resp.statusCode != 201) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return RoomHandle(
      transport: this,
      code: j['room_code'] as String,
      wsUrl: j['ws_url'] as String,
      initial: Snapshot.fromJson(j['snapshot'] as Map<String, dynamic>),
    );
  }

  Future<RoomHandle> joinRoom({required String code}) async {
    final resp = await _http.post(
      _u('/api/v3/relay/rooms/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId, 'alias': alias}),
    );
    if (resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return RoomHandle(
      transport: this,
      code: code,
      wsUrl: j['ws_url'] as String,
      initial: Snapshot.fromJson(j['snapshot'] as Map<String, dynamic>),
    );
  }

  Future<Snapshot> fetchSnapshot(String code) async {
    final resp = await _http.get(_u('/api/v3/relay/rooms/$code/snapshot'));
    if (resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return Snapshot.fromJson(j['snapshot'] as Map<String, dynamic>);
  }

  Future<Snapshot> _applyAction({
    required String code,
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    required String sourceDeviceId,
  }) async {
    final body = <String, dynamic>{
      'type': type,
      'params': params,
      'source_device_id': sourceDeviceId,
    };
    if (expectVersion != null) body['expect_version'] = expectVersion;
    final resp = await _http.post(
      _u('/api/v3/relay/rooms/$code/actions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return Snapshot.fromJson(j['snapshot'] as Map<String, dynamic>);
  }

  Future<void> _leave({required String code, required String deviceId}) async {
    final resp = await _http.post(
      _u('/api/v3/relay/rooms/$code/leave'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId}),
    );
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
  }

  // Test-only public access to internal _applyAction.
  @visibleForTesting
  Future<Snapshot> applyActionPublic({
    required String code,
    required String type,
    required Map<String, dynamic> params,
    String? sourceDeviceId,
  }) =>
      _applyAction(
        code: code,
        type: type,
        params: params,
        sourceDeviceId: sourceDeviceId ?? deviceId,
      );
}

class RelayV3Exception implements Exception {
  final int statusCode;
  final String body;
  RelayV3Exception(this.statusCode, this.body);

  @override
  String toString() => 'RelayV3Exception($statusCode): $body';
}