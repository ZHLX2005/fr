import 'dart:async';

import 'package:xiaodouzi_fr/api/goframe/room/room_endpoint.dart';

import '../transport/transport_kind.dart';
import 'discovery_event.dart';
import 'discovery_peer.dart';
import 'discovery_service.dart';

/// Relay 发现服务 — 通过 HTTP 房间 API + WS 通知完成发现
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

  final StreamController<DiscoveryEvent> _ctrl =
      StreamController<DiscoveryEvent>.broadcast();
  bool _started = false;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
  }

  @override
  List<DiscoveryPeer> get peers => const [];

  @override
  Stream<DiscoveryEvent> get events => _ctrl.stream;

  @override
  Future<String?> createRoom({String? alias}) async {
    final result = await _roomEndpoint.createRoom(
      alias: alias ?? myAlias,
      deviceId: myDeviceId,
    );
    _ctrl.add(RoomCreated(
      roomCode: result.roomCode,
      hostAlias: alias ?? myAlias,
    ));
    return result.roomCode;
  }

  @override
  Future<DiscoveryEvent?> joinRoom(String roomCode, {String? alias}) async {
    try {
      final result = await _roomEndpoint.joinRoom(
        roomCode: roomCode,
        deviceId: myDeviceId,
        alias: alias ?? myAlias,
      );
      final host = DiscoveryPeer(
        deviceId: result.hostDeviceId,
        alias: result.hostAlias,
        address: 'relay:$roomCode',
        kind: TransportKind.relay,
        lastSeen: DateTime.now(),
      );
      final ev = RoomJoined(roomCode: roomCode, host: host);
      _ctrl.add(ev);
      return ev;
    } on RoomNotFoundException {
      final ev = RoomNotFound(roomCode);
      _ctrl.add(ev);
      return ev;
    } on RoomFullException {
      final ev = RoomFull(roomCode);
      _ctrl.add(ev);
      return ev;
    }
  }

  @override
  Future<void> leaveRoom() async {
    if (_started) {
      _ctrl.add(RoomLeft(''));
    }
  }
}
