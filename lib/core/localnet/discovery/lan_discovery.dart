import 'dart:async';
import 'dart:convert';

import '../transport/transport_kind.dart';
import '../transport/udp_transport.dart';
import 'discovery_event.dart';
import 'discovery_peer.dart';
import 'discovery_service.dart';

/// LAN 发现服务 — 监听 UDP 多播心跳包
class LanDiscovery implements DiscoveryService {
  LanDiscovery({
    required this.myDeviceId,
    required this.myAlias,
    required UdpTransport udp,
  }) : _udp = udp;

  final String myDeviceId;
  final String myAlias;
  final UdpTransport _udp;

  final Map<String, DiscoveryPeer> _peers = {};
  final StreamController<DiscoveryEvent> _ctrl =
      StreamController<DiscoveryEvent>.broadcast();
  StreamSubscription? _sub;
  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _sub = _udp.datagrams.listen(_onDatagram);
    _started = true;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _peers.clear();
    _started = false;
  }

  @override
  List<DiscoveryPeer> get peers => List.unmodifiable(_peers.values);

  @override Stream<DiscoveryEvent> get events => _ctrl.stream;

  @override
  Future<String?> createRoom({String? alias}) => Future.value(null);

  @override
  Future<DiscoveryEvent?> joinRoom(String roomCode, {String? alias}) =>
      Future.value(null);

  @override
  Future<void> leaveRoom() => Future.value();

  void _onDatagram(dynamic dg) {
    final data = dg.data as List<int>;
    final sender = dg.senderAddress;
    final text = utf8.decode(data, allowMalformed: true);
    if (!text.contains(',')) return;

    final parts = text.split(',');
    if (parts.length < 2) return;
    final id = parts[0].trim();
    final portStr = parts[1].trim();
    final port = int.tryParse(portStr);
    if (id.isEmpty || port == null) return;
    if (id == myDeviceId) return; // 忽略自己

    String alias = sender.address.toString();
    for (var i = 2; i < parts.length; i++) {
      final kv = parts[i].split(':');
      if (kv.length == 2 && kv[0].trim() == 'alias') {
        alias = kv[1].trim();
        break;
      }
    }

    final peer = DiscoveryPeer(
      deviceId: id,
      alias: alias,
      address: '${sender.address}:$port',
      kind: TransportKind.lan,
      lastSeen: DateTime.now(),
    );
    if (!_peers.containsKey(id)) {
      _peers[id] = peer;
      _ctrl.add(PeerFound(peer));
    } else {
      _peers[id] = peer;
    }
  }
}
