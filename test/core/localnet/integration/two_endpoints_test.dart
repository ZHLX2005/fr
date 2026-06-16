import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';

void main() {
  // 集成测试：两个框架实例通信
  group('LanFramework 集成', () {
    test('两个框架实例互相发现', () async {
      // 注：单例限制下无法同时跑两个实例，改为手工测试覆盖
      // 这里仅验证 framework 启动后能正常启动
      final fw = LanFramework.instance;
      await fw.stop();

      const cfg = FrameworkConfig(
        deviceAlias: 'IntegratedTest',
        port: 0,
      );
      await fw.start(cfg);
      expect(fw.status.name, 'running');

      await fw.stop();
    }, skip: '需要双进程或两台设备；单进程内单例限制');
  });
}
