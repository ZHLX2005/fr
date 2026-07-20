import 'dart:async';

import 'package:xiaodouzi_fr/api/goframe/room/room_endpoint.dart';

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
    this.relayHttpPath = '/api/v1/relay',
    RoomEndpoint? roomEndpoint,
  }) : _roomEndpoint = roomEndpoint ?? RoomEndpoint(
         baseUrl: relayUrl,
         pathPrefix: relayHttpPath,
       );

  final String relayUrl;
  final String relayHttpPath;
  final String myDeviceId;
  final String myAlias;
  final RoomEndpoint _roomEndpoint;

  final List<RemoteEndpoint> _endpoints = [];
  final StreamController<List<RemoteEndpoint>> _ctrl =
      StreamController<List<RemoteEndpoint>>.broadcast();

  @override
  Future<void> start() async {
  }

  @override
  Future<void> stop() async {
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
    final result = await _roomEndpoint.createRoom(
      alias: myAlias,
      deviceId: myDeviceId,
    );
    return RelayRoomInfo(roomCode: result.roomCode, wsUrl: result.wsUrl);
  }

  /// 加入房间 — 返回 host 端点及服务器提供的 WebSocket URL。
  ///
  /// 服务端响应必须包含 `wsUrl`，客户端不会自行拼接中继地址。
  Future<RelayJoinResult> joinRoom({required String roomCode}) async {
    try {
      final result = await _roomEndpoint.joinRoom(
        roomCode: roomCode,
        deviceId: myDeviceId,
        alias: myAlias,
      );
      return RelayJoinResult(
        host: RemoteEndpoint(
          deviceId: result.hostDeviceId,
          alias: result.hostAlias,
          address: 'relay:$roomCode',
          kind: TransportKind.relay,
          lastSeen: DateTime.now(),
        ),
        wsUrl: result.wsUrl,
      );
    } on RoomNotFoundException catch (e) {
      throw RoomNotFoundError(e.message);
    } on RoomFullException catch (e) {
      throw RoomFullError(e.message);
    } on RoomEndpointException catch (e) {
      throw RelayUnreachableError(e.message);
    }
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
  RelayUnreachableError(super.message);
}

/// 房间号不存在
class RoomNotFoundError extends FrameworkException {
  RoomNotFoundError(super.message);
}

/// 房间已满（2 人上限）
class RoomFullError extends FrameworkException {
  RoomFullError(super.message);
}
