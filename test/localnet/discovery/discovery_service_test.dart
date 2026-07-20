import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/discovery_peer.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/discovery_event.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/discovery_service.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';

class _FakeDiscovery implements DiscoveryService {
  final List<DiscoveryPeer> _peers = [];
  final _controller = StreamController<DiscoveryEvent>.broadcast();
  bool started = false;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  List<DiscoveryPeer> get peers => List.unmodifiable(_peers);

  @override
  Stream<DiscoveryEvent> get events => _controller.stream;

  @override
  Future<String?> createRoom({String? alias}) => Future.value(null);

  @override
  Future<DiscoveryEvent?> joinRoom(String roomCode, {String? alias}) =>
      Future.value(null);

  @override
  Future<void> leaveRoom() => Future.value();

  void addForTesting(DiscoveryPeer peer) {
    _peers.add(peer);
    _controller.add(PeerFound(peer));
  }
}

void main() {
  group('DiscoveryService contract', () {
    test('implements start/stop', () async {
      final fake = _FakeDiscovery();
      await fake.start();
      expect(fake.started, isTrue);
      await fake.stop();
      expect(fake.started, isFalse);
    });

    test('peers is unmodifiable', () {
      final fake = _FakeDiscovery();
      fake.addForTesting(DiscoveryPeer(
        deviceId: 'd1',
        alias: 'Alice',
        address: '192.168.1.5:53317',
        kind: TransportKind.lan,
        lastSeen: DateTime.now(),
      ));
      expect(fake.peers, hasLength(1));
      expect(() => fake.peers.clear(), throwsUnsupportedError);
    });

    test('events stream emits PeerFound on add', () async {
      final fake = _FakeDiscovery();
      final received = <DiscoveryEvent>[];
      final sub = fake.events.listen(received.add);
      fake.addForTesting(DiscoveryPeer(
        deviceId: 'd1',
        alias: 'Alice',
        address: '192.168.1.5:53317',
        kind: TransportKind.lan,
        lastSeen: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(received, hasLength(1));
      expect(received.first, isA<PeerFound>());
      expect((received.first as PeerFound).peer.deviceId, 'd1');
      await sub.cancel();
    });
  });
}
