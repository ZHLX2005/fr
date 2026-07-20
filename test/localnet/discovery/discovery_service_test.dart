import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/remote_endpoint.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/discovery_service.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';

class _FakeDiscovery implements DiscoveryService {
  final List<RemoteEndpoint> _endpoints = [];
  final _controller = StreamController<List<RemoteEndpoint>>.broadcast();
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
  List<RemoteEndpoint> get endpoints => List.unmodifiable(_endpoints);

  @override
  Stream<List<RemoteEndpoint>> watch() => _controller.stream;

  @override
  Future<void> probe() async {
    _controller.add(List.unmodifiable(_endpoints));
  }

  void addForTesting(RemoteEndpoint ep) {
    _endpoints.add(ep);
    _controller.add(List.unmodifiable(_endpoints));
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

    test('endpoints is unmodifiable', () {
      final fake = _FakeDiscovery();
      fake.addForTesting(RemoteEndpoint(
        deviceId: 'd1',
        alias: 'Alice',
        address: '192.168.1.5:53317',
        kind: TransportKind.lan,
        lastSeen: DateTime.now(),
      ));
      expect(fake.endpoints, hasLength(1));
      expect(() => fake.endpoints.clear(), throwsUnsupportedError);
    });

    test('watch emits current list on probe', () async {
      final fake = _FakeDiscovery();
      final received = <List<RemoteEndpoint>>[];
      final sub = fake.watch().listen(received.add);
      fake.addForTesting(RemoteEndpoint(
        deviceId: 'd1',
        alias: 'Alice',
        address: '192.168.1.5:53317',
        kind: TransportKind.lan,
        lastSeen: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(received, hasLength(1));
      expect(received.first.first.deviceId, 'd1');
      await sub.cancel();
    });
  });
}