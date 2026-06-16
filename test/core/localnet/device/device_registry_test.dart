import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device_registry.dart';

void main() {
  group('DeviceRegistry', () {
    late DeviceRegistry registry;

    setUp(() {
      registry = DeviceRegistry();
    });

    test('add 后 get 能找到设备', () {
      final d = Device(
        deviceId: 'a',
        alias: 'A',
        ip: '192.168.1.1',
        port: 53317,
        lastSeen: DateTime.now(),
        extras: {},
      );
      registry.add(d);
      expect(registry.get('a'), equals(d));
    });

    test('重复 add 同一 id 应更新', () {
      final t1 = DateTime(2026, 1, 1);
      final t2 = DateTime(2026, 1, 2);
      registry.add(Device(deviceId: 'a', alias: 'A', ip: '1.1.1.1', port: 1, lastSeen: t1, extras: {}));
      registry.add(Device(deviceId: 'a', alias: 'A2', ip: '2.2.2.2', port: 2, lastSeen: t2, extras: {}));

      final got = registry.get('a')!;
      expect(got.alias, 'A2');
      expect(got.ip, '2.2.2.2');
      expect(got.lastSeen, t2);
    });

    test('remove 后 get 返回 null', () {
      final d = Device(deviceId: 'a', alias: 'A', ip: '1.1.1.1', port: 1, lastSeen: DateTime.now(), extras: {});
      registry.add(d);
      registry.remove('a');
      expect(registry.get('a'), isNull);
    });

    test('all 返回所有设备的不可变列表', () {
      registry.add(Device(deviceId: 'a', alias: 'A', ip: '1.1.1.1', port: 1, lastSeen: DateTime.now(), extras: {}));
      registry.add(Device(deviceId: 'b', alias: 'B', ip: '2.2.2.2', port: 2, lastSeen: DateTime.now(), extras: {}));
      final all = registry.all;
      expect(all.length, 2);
      expect(() => all.add(Device(deviceId: 'c', alias: 'C', ip: '3.3.3.3', port: 3, lastSeen: DateTime.now(), extras: {})), throwsUnsupportedError);
    });

    test('cleanupStale 返回被清理的设备 id 列表', () {
      final now = DateTime.now();
      registry.add(Device(deviceId: 'fresh', alias: 'F', ip: '1.1.1.1', port: 1, lastSeen: now, extras: {}));
      registry.add(Device(deviceId: 'stale', alias: 'S', ip: '1.1.1.1', port: 1, lastSeen: now.subtract(const Duration(seconds: 30)), extras: {}));

      final removed = registry.cleanupStale(timeout: const Duration(seconds: 10));
      expect(removed, contains('stale'));
      expect(removed, isNot(contains('fresh')));
      expect(registry.get('stale'), isNull);
    });
  });
}
