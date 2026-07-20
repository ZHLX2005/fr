import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_status.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';

void main() {
  final framework = LanFramework.instance;

  tearDown(() async {
    await framework.stop();
  });

  test('start with relay transport uses relay core', () async {
    await framework.start(
      const FrameworkConfig(
        transportKind: TransportKind.relay,
        relayUrl: 'https://relay.example.com',
        deviceId: 'self-relay',
        deviceAlias: 'SelfRelay',
        httpServerEnabled: false,
        udpListenerEnabled: false,
        udpBroadcastEnabled: false,
      ),
    );

    expect(framework.status, FrameworkStatus.running);
    expect(framework.myDeviceId, 'self-relay');
  });

  test('Relay mode sendMulticast throws UnsupportedError (LAN-only)', () async {
    await framework.start(
      const FrameworkConfig(
        transportKind: TransportKind.relay,
        relayUrl: 'https://relay.example.com',
        deviceId: 'self',
        deviceAlias: 'Self',
      ),
    );

    expect(
      () => framework.sendMulticast(key: 'test', payload: const {}),
      throwsUnsupportedError,
    );
  });

  test('Relay mode watchMulticast throws UnsupportedError (LAN-only)', () async {
    await framework.start(
      const FrameworkConfig(
        transportKind: TransportKind.relay,
        relayUrl: 'https://relay.example.com',
        deviceId: 'self',
        deviceAlias: 'Self',
      ),
    );

    expect(() => framework.watchMulticast(), throwsUnsupportedError);
  });

  test('sendTo/wathChannel work in relay mode (now unified API)', () async {
    await framework.start(
      const FrameworkConfig(
        transportKind: TransportKind.relay,
        relayUrl: 'https://relay.example.com',
        deviceId: 'self',
        deviceAlias: 'Self',
      ),
    );

    // Now sendTo/watchChannel are unified — they return send results / streams
    // without throwing, even in relay mode (they delegate to TransportService)
    expect(framework.sendTo('peer', 'test', const {}), isA<Future>());
    expect(framework.watchChannel('test'), isA<Stream>());
  });

  test('start with default transport uses LAN core', () async {
    await framework.start(
      const FrameworkConfig(
        deviceId: 'self-lan',
        deviceAlias: 'SelfLan',
        port: 0,
        udpListenerEnabled: false,
        udpBroadcastEnabled: false,
      ),
    );

    expect(framework.status, FrameworkStatus.running);
    expect(framework.myDeviceId, 'self-lan');
  });
}
