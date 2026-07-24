// lib/core/net_engine/relay_snapshot/relay_snapshot_transport.dart
//
// 快照驱动 relay transport — 对应后端 /api/v2/relay_snapshot/
//
// 与 RelayTransport 的核心差异：
//   - 没有 subscribe/unsubscribe 协议 — 连 WS 即订阅 snapshot/<code>
//   - 服务端任何状态变更广播完整 snapshot（不是事件）
//   - 客户端收到 snapshot 后整体替换本地 state，无需合并
//
// API surface:
//   createRoom(...)  -> RoomHandle
//   joinRoom(code)   -> RoomHandle
//   handle.snapshot  -> 当前快照 (Stream<Snapshot>)
//   handle.applyAction(type, payload)  -> 业务动作
//   handle.leave()   -> 断开

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 玩家
class SnapshotPlayer {
  final String deviceId;
  final String alias;
  final String role;
  final bool online;
  SnapshotPlayer({
    required this.deviceId,
    required this.alias,
    this.role = '',
    this.online = true,
  });

  factory SnapshotPlayer.fromJson(Map<String, dynamic> j) => SnapshotPlayer(
        deviceId: j['deviceId'] as String? ?? '',
        alias: j['alias'] as String? ?? '?',
        role: j['role'] as String? ?? '',
        online: j['online'] as bool? ?? true,
      );
}

/// 房间快照（一个 JSON 对象描述整个房间状态）
class Snapshot {
  final String code;
  final SnapshotPlayer host;
  final List<SnapshotPlayer> players;
  final int maxPlayers;
  final Map<String, dynamic> schema;
  final String status;
  final int version;
  final Map<String, dynamic> custom;

  Snapshot({
    required this.code,
    required this.host,
    required this.players,
    required this.maxPlayers,
    required this.schema,
    required this.status,
    required this.version,
    required this.custom,
  });

  factory Snapshot.fromJson(Map<String, dynamic> j) {
    final hostJson = (j['host'] as Map?)?.cast<String, dynamic>() ?? const {};
    final playersJson = (j['players'] as List?) ?? const [];
    return Snapshot(
      code: j['code'] as String? ?? '',
      host: SnapshotPlayer.fromJson(hostJson),
      players: playersJson
          .whereType<Map>()
          .map((p) => SnapshotPlayer.fromJson(p.cast<String, dynamic>()))
          .toList(),
      maxPlayers: (j['maxPlayers'] as num?)?.toInt() ?? 2,
      schema: (j['schema'] as Map?)?.cast<String, dynamic>() ?? const {},
      status: j['status'] as String? ?? 'waiting',
      version: (j['version'] as num?)?.toInt() ?? 0,
      custom: (j['custom'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  SnapshotPlayer? playerByDevice(String deviceId) {
    if (host.deviceId == deviceId) return host;
    for (final p in players) {
      if (p.deviceId == deviceId) return p;
    }
    return null;
  }
}

/// 一个房间的运行时句柄
class RoomHandle {
  RoomHandle._({
    required this.transport,
    required this.code,
    required this.wsUrl,
    required this.myDeviceId,
  });

  final RelaySnapshotTransport transport;
  final String code;
  final String wsUrl;
  final String myDeviceId;

  WebSocketChannel? _ws;
  StreamSubscription? _sub;

  final _snapshotCtrl = StreamController<Snapshot>.broadcast();
  Stream<Snapshot> get snapshots => _snapshotCtrl.stream;

  Snapshot? _latest;
  Snapshot? get latest => _latest;

  bool _connected = false;
  bool get isConnected => _connected;

  /// 连接到 WS，开始接收 snapshot
  Future<void> connect() async {
    if (_connected) return;
    final ws = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    _ws = ws;
    // identify frame
    ws.sink.add(jsonEncode({
      'channelName': 'identify',
      'sourceDeviceId': myDeviceId,
      'payload': base64Encode(utf8.encode(jsonEncode({
        'alias': transport.alias,
      }))),
      'timestamp': DateTime.now().toIso8601String(),
    }));
    _sub = ws.stream.listen(_onFrame);
    _connected = true;
  }

  void _onFrame(dynamic data) {
    if (data is! String) return;
    try {
      final env = jsonDecode(data) as Map<String, dynamic>;
      final ch = env['channelName'] as String? ?? '';
      if (ch == 'identify' || ch.isEmpty) return;
      // 服务端 broadcast 的 snapshot 在 payload 字段
      final payloadStr = env['payload'];
      if (payloadStr is! String || payloadStr.isEmpty) return;
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      final snap = Snapshot.fromJson(payload);
      _latest = snap;
      _snapshotCtrl.add(snap);
    } catch (_) {}
  }

  /// 提交业务动作（chat / start / deal / ...）
  Future<void> applyAction(String type, Map<String, dynamic> payload) async {
    await transport._http.post(
      Uri.parse('${transport.relayUrl}/api/v2/relay_snapshot/rooms/$code/action'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'deviceId': myDeviceId,
        'type': type,
        'payload': payload,
      }),
    );
  }

  /// 断开
  Future<void> leave() async {
    await _sub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    _sub = null;
    _connected = false;
  }

  Future<void> dispose() async {
    await leave();
    await _snapshotCtrl.close();
  }
}

/// Transport — 创建/加入房间 + 持有 HTTP 客户端
class RelaySnapshotTransport {
  RelaySnapshotTransport({required this.relayUrl, required this.alias, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String relayUrl;
  final String alias;
  final http.Client _http;

  final String deviceId =
      '${DateTime.now().microsecondsSinceEpoch}-${DateTime.now().millisecondsSinceEpoch % 1000}';

  /// 房主建房
  Future<RoomHandle> createRoom({int maxPlayers = 2, Map<String, dynamic> schema = const {}}) async {
    final resp = await _http.post(
      Uri.parse('$relayUrl/api/v2/relay_snapshot/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId,
        'alias': alias,
        'maxPlayers': maxPlayers,
        'schema': schema,
      }),
    );
    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw StateError('创建房间失败: HTTP ${resp.statusCode}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final handle = RoomHandle._(
      transport: this,
      code: j['roomCode'] as String,
      wsUrl: j['wsUrl'] as String,
      myDeviceId: deviceId,
    );
    await handle.connect();
    return handle;
  }

  /// 玩家加入
  Future<RoomHandle> joinRoom(String code) async {
    final resp = await _http.post(
      Uri.parse('$relayUrl/api/v2/relay_snapshot/rooms/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceId': deviceId,
        'alias': alias,
        'code': code,
      }),
    );
    if (resp.statusCode != 200) {
      throw StateError('加入失败: HTTP ${resp.statusCode}');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final handle = RoomHandle._(
      transport: this,
      code: j['roomCode'] as String,
      wsUrl: j['wsUrl'] as String,
      myDeviceId: deviceId,
    );
    await handle.connect();
    return handle;
  }

  void close() => _http.close();
}