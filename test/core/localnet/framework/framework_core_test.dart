import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_core.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';

void main() {
  group('FrameworkCore', () {
    test('start 后 isRunning 为 true；stop 后为 false', () async {
      final core = FrameworkCore(
        myDeviceId: 'self-1',
        myAlias: 'Test',
        transportConfig: TransportConfig(httpPort: 0, multicastPort: 5682),
      );
      await core.start();
      expect(core.isRunning, isTrue);
      await core.stop();
      expect(core.isRunning, isFalse);
      await core.dispose();
    });

    test('重复 start 应幂等', () async {
      final core = FrameworkCore(
        myDeviceId: 'self-2',
        transportConfig: TransportConfig(httpPort: 0, multicastPort: 5683),
      );
      await core.start();
      await core.start(); // 不应抛
      expect(core.isRunning, isTrue);
      await core.stop();
      await core.dispose();
    });
  });
}
