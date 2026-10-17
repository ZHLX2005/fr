// 验证 RelayDeviceId 自动生成的唯一性：
// 两个"全新安装"（清空 prefs）必须生成不同的 device_id。
// 如果本测试通过，说明生成机制无 bug——
// 真机上两设备同 id 只能是 app 数据同源（克隆镜像/备份恢复）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_device_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('两次全新安装生成不同 device_id', () async {
    // 安装 A：空 prefs
    SharedPreferences.setMockInitialValues({});
    RelayDeviceId.debugReset();
    final idA = await RelayDeviceId.get();

    // 安装 B：空 prefs（另一台设备全新安装）
    SharedPreferences.setMockInitialValues({});
    RelayDeviceId.debugReset();
    final idB = await RelayDeviceId.get();

    expect(idA, isNotEmpty);
    expect(idB, isNotEmpty);
    expect(idA, isNot(idB), reason: '两个全新安装的 device_id 不应相同');
    expect(idA.startsWith('dev-'), isTrue);
  });

  test('同一安装内 get() 稳定复用（不换 id）', () async {
    SharedPreferences.setMockInitialValues({});
    RelayDeviceId.debugReset();
    final id1 = await RelayDeviceId.get();
    final id2 = await RelayDeviceId.get(); // 走 _cached
    RelayDeviceId.debugReset();
    final id3 = await RelayDeviceId.get(); // 走 prefs 持久化
    expect(id1, id2);
    expect(id1, id3);
  });

  test('批量生成 1000 个无碰撞（UUID v4 随机性）', () async {
    final ids = <String>{};
    for (var i = 0; i < 1000; i++) {
      SharedPreferences.setMockInitialValues({});
      RelayDeviceId.debugReset();
      ids.add(await RelayDeviceId.get());
    }
    expect(ids.length, 1000, reason: '1000 次生成应全部唯一');
  });
}