import 'dart:convert';

import 'package:http/http.dart' as http;

/// Room 端点 — 通过中继服务器创建/加入房间
///
/// 不走 ApiClient 拦截器链（relay 床的响应不遵循 GoFrame {code, message, data} 包裹格式）。
class RoomEndpoint {
  final String baseUrl;
  final String pathPrefix;
  final http.Client _client;

  RoomEndpoint({
    required this.baseUrl,
    this.pathPrefix = '/api/v1',
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client();

  String get _roomsUrl => '$baseUrl$pathPrefix/rooms';

  Future<RoomCreateResult> createRoom({
    required String alias,
    required String deviceId,
  }) async {
    final uri = Uri.parse(_roomsUrl);
    final resp = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'alias': alias, 'deviceId': deviceId}),
    );
    if (resp.statusCode != 201) {
      throw RoomEndpointException('创建房间失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return RoomCreateResult(
      roomCode: json['roomCode'] as String,
      wsUrl: json['wsUrl'] as String,
    );
  }

  Future<RoomJoinResult> joinRoom({required String roomCode}) async {
    final uri = Uri.parse('$_roomsUrl/$roomCode');
    final resp = await _client.get(uri);
    if (resp.statusCode == 404) {
      throw RoomNotFoundException('房间 $roomCode 不存在');
    }
    if (resp.statusCode == 409) {
      throw RoomFullException('房间 $roomCode 已满');
    }
    if (resp.statusCode != 200) {
      throw RoomEndpointException('加入房间失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final wsUrl = json['wsUrl'] as String?;
    if (wsUrl == null || wsUrl.isEmpty) {
      throw RoomEndpointException('加入房间响应缺少 wsUrl');
    }
    return RoomJoinResult(
      hostDeviceId: json['hostDeviceId'] as String,
      hostAlias: json['hostAlias'] as String? ?? 'Host',
      wsUrl: wsUrl,
    );
  }

  void dispose() => _client.close();
}

/// 创建房间结果
class RoomCreateResult {
  final String roomCode;
  final String wsUrl;
  const RoomCreateResult({required this.roomCode, required this.wsUrl});
}

/// 加入房间结果
class RoomJoinResult {
  final String hostDeviceId;
  final String hostAlias;
  final String wsUrl;
  const RoomJoinResult({
    required this.hostDeviceId,
    required this.hostAlias,
    required this.wsUrl,
  });
}

/// Room 端点异常
class RoomEndpointException implements Exception {
  final String message;
  RoomEndpointException(this.message);
  @override
  String toString() => message;
}

/// 房间不存在
class RoomNotFoundException extends RoomEndpointException {
  RoomNotFoundException(super.message);
}

/// 房间已满
class RoomFullException extends RoomEndpointException {
  RoomFullException(super.message);
}
