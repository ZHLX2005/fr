import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../framework/exception/framework_exception.dart';
import '../transport/transport_kind.dart';
import 'discovery_service.dart';
import 'remote_endpoint.dart';

/// Relay 后端发现服务 — 通过 HTTP 短调用与中继服务器交互
///
/// 协议契约：
/// - POST /rooms                  → 创建房间，返回 roomCode + wsUrl
/// - GET  /rooms/{code}           → 查询房间元信息（用于 join 验证）
class RelayDiscovery implements DiscoveryService {
  RelayDiscovery({
    required this.relayUrl,
    required this.myDeviceId,
    required this.myAlias,
    this.relayHttpPath = '/api/v1',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String relayUrl;
  final String relayHttpPath;
  final String myDeviceId;
  final String myAlias;
  final http.Client _http;

  final List<RemoteEndpoint> _endpoints = [];
  final StreamController<List<RemoteEndpoint>> _ctrl =
      StreamController<List<RemoteEndpoint>>.broadcast();
  bool _started = false;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
    _endpoints.clear();
    await _ctrl.close();
  }

  @override
  List<RemoteEndpoint> get endpoints => List.unmodifiable(_endpoints);

  @override
  Stream<List<RemoteEndpoint>> watch() => _ctrl.stream;

  @override
  Future<void> probe() async {
    _ctrl.add(endpoints);
  }

  /// 创建房间 — 返回 roomCode + wsUrl
  Future<RelayRoomInfo> createRoom() async {
    final resp = await _http.post(
      Uri.parse('$relayUrl$relayHttpPath/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'alias': myAlias, 'deviceId': myDeviceId}),
    );
    if (resp.statusCode != 201) {
      throw RelayUnreachableError('createRoom failed: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return RelayRoomInfo(
      roomCode: json['roomCode'] as String,
      wsUrl: json['wsUrl'] as String,
    );
  }

  /// 加入房间 — 返回 host 端点及服务器提供的 WebSocket URL。
  ///
  /// 服务端响应必须包含 `wsUrl`，客户端不会自行拼接中继地址。
  Future<RelayJoinResult> joinRoom({required String roomCode}) async {
    final resp = await _http.get(
      Uri.parse('$relayUrl$relayHttpPath/rooms/$roomCode'),
    );
    if (resp.statusCode == 404) {
      throw RoomNotFoundError('Room $roomCode not found');
    }
    if (resp.statusCode == 409) {
      throw RoomFullError('Room $roomCode is full');
    }
    if (resp.statusCode != 200) {
      throw RelayUnreachableError('joinRoom failed: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final wsUrl = json['wsUrl'] as String?;
    if (wsUrl == null || wsUrl.isEmpty) {
      throw RelayUnreachableError('joinRoom response missing wsUrl');
    }
    return RelayJoinResult(
      host: RemoteEndpoint(
        deviceId: json['hostDeviceId'] as String,
        alias: json['hostAlias'] as String? ?? 'Host',
        address: 'relay:$roomCode',
        kind: TransportKind.relay,
        lastSeen: DateTime.now(),
      ),
      wsUrl: wsUrl,
    );
  }
}

/// createRoom 返回的房间信息
class RelayRoomInfo {
  const RelayRoomInfo({required this.roomCode, required this.wsUrl});
  final String roomCode;
  final String wsUrl;
}

/// joinRoom 返回的主机端点和服务器指定的 WebSocket URL。
class RelayJoinResult {
  const RelayJoinResult({required this.host, required this.wsUrl});

  final RemoteEndpoint host;
  final String wsUrl;
}

/// Relay 不可达（HTTP 5xx / 超时）
class RelayUnreachableError extends FrameworkException {
  RelayUnreachableError(String message) : super(message);
}

/// 房间号不存在
class RoomNotFoundError extends FrameworkException {
  RoomNotFoundError(String message) : super(message);
}

/// 房间已满（2 人上限）
class RoomFullError extends FrameworkException {
  RoomFullError(String message) : super(message);
}
