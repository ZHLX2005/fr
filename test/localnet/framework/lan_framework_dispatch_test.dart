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
