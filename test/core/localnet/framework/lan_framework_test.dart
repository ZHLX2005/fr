import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_status.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';

void main() {
  group('LanFramework', () {
    test('start/stop 状态机正确', () async {
      final fw = LanFramework.instance;
      const cfg = FrameworkConfig(
        deviceAlias: 'Test',
        port: 0, // 系统分配
      );
      // 由于是单例，先 stop 防止重入
      await fw.stop();

      await fw.start(cfg);
      expect(fw.status, FrameworkStatus.running);

      await fw.stop();
      expect(fw.status, FrameworkStatus.init);
    });
  });
}
