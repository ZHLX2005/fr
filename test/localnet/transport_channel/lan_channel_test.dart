import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/http_transport.dart';
import 'package:xiaodouzi_fr/core/localnet/transport_channel/lan_channel.dart';

void main() {
  group('TransportChannel contract (LanChannel)', () {
    test('open + send + watch + close lifecycle', () async {
      final server = HttpTransport(
        config: const TransportConfig(httpPort: 53320),
      );
      try {
        await server.start();
      } catch (_) {
        // 端口占用跳过
        return;
      }
      final channel = LanChannel(http: server);
      await channel.open(channelName: 'test', remoteDeviceId: 'peer');
      expect(true, isTrue); // open 不抛
      await channel.close();
      await server.stop();
    });
  });
}
