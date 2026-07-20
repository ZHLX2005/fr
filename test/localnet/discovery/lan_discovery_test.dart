import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/lan_discovery.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/remote_endpoint.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/udp_transport.dart';

void main() {
  group('LanDiscovery', () {
    late UdpTransport udp;
    late LanDiscovery discovery;
    final config = const TransportConfig(
      multicastAddress: '239.255.255.255',
      multicastPort: 5678,
    );

    setUp(() async {
      udp = UdpTransport(config: config);
      try {
        await udp.start();
      } catch (_) {
        // 端口占用时跳过集成测试
      }
      discovery = LanDiscovery(
        myDeviceId: 'self-id',
        myAlias: 'Self',
        udp: udp,
      );
    });

    tearDown(() async {
      await discovery.stop();
      await udp.stop();
    });

    test('start/stop toggles internal state', () async {
      await discovery.start();
      expect(discovery.endpoints, isEmpty);
      await discovery.stop();
    });

    test('endpoints returns empty list initially', () {
      expect(discovery.endpoints, isEmpty);
    });

    test('watch() emits at least once on probe', () async {
      await discovery.start();
      final received = <List<RemoteEndpoint>>[];
      final sub = discovery.watch().listen(received.add);
      await discovery.probe();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(received, isNotEmpty);
      await sub.cancel();
      await discovery.stop();
    });
  });
}