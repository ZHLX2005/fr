import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device_manager.dart';
import 'package:xiaodouzi_fr/core/localnet/event_bus/event_bus.dart';
import 'package:xiaodouzi_fr/core/localnet/event_bus/lan_event.dart';

void main() {
  group('DeviceManager', () {
    late EventBus bus;
    late DeviceManager mgr;
    late StreamSubscription sub;

    setUp(() {
      bus = EventBus();
      mgr = DeviceManager(
        eventBus: bus,
        myDeviceId: 'self',
        myAlias: 'Self',
        timeout: const Duration(seconds: 10),
      );
    });

    tearDown(() async {
      await sub.cancel();
      await mgr.dispose();
      bus.dispose();
    });

    test('onDatagram 添加新设备并发射 DeviceFoundEvent', () async {
      final received = <String>[];
      sub = bus.watch<DeviceFoundEvent>().listen((e) => received.add(e.deviceId));

      mgr.onDatagram(deviceId: 'remote-1', ip: '192.168.1.5', port: 53317);

      await Future<void>.delayed(Duration.zero);
      expect(received, ['remote-1']);
      expect(mgr.devices.length, 1);
    });

    test('onDatagram 同 deviceId 重复到达不重复发射 DeviceFoundEvent', () async {
      var count = 0;
      sub = bus.watch<DeviceFoundEvent>().listen((_) => count++);

      mgr.onDatagram(deviceId: 'remote-1', ip: '1.1.1.1', port: 53317);
      mgr.onDatagram(deviceId: 'remote-1', ip: '1.1.1.1', port: 53317);
      mgr.onDatagram(deviceId: 'remote-1', ip: '1.1.1.1', port: 53317);

      await Future<void>.delayed(Duration.zero);
      expect(count, 1);
    });

    test('cleanupNow 返回离线设备并发射 DeviceLostEvent', () async {
      final lostIds = <String>[];
      sub = bus.watch<DeviceLostEvent>().listen((e) => lostIds.add(e.deviceId));

      mgr.onDatagram(deviceId: 'stale', ip: '1.1.1.1', port: 1);
      // 手动改 lastSeen 让它超时
      mgr.debugForceLastSeen('stale', DateTime.now().subtract(const Duration(seconds: 60)));

      final removed = mgr.cleanupNow();
      expect(removed, contains('stale'));
      await Future<void>.delayed(Duration.zero);
      expect(lostIds, contains('stale'));
    });

    test('updateAlias 触发 DeviceUpdatedEvent', () async {
      final updates = <String>[];
      sub = bus.watch<DeviceUpdatedEvent>().listen((e) => updates.add(e.alias));

      mgr.onDatagram(deviceId: 'remote-1', ip: '1.1.1.1', port: 53317);
      mgr.updateAlias('remote-1', 'NewName');

      await Future<void>.delayed(Duration.zero);
      expect(updates, contains('NewName'));
      expect(mgr.getDevice('remote-1')?.alias, 'NewName');
    });
  });
}
