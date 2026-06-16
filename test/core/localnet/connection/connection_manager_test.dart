import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/connection/connection_manager.dart';
import 'package:xiaodouzi_fr/core/localnet/connection/connection_quality.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device_manager.dart';
import 'package:xiaodouzi_fr/core/localnet/event_bus/lan_event.dart';
import 'package:xiaodouzi_fr/core/localnet/event_bus/event_bus.dart';

void main() {
  group('ConnectionManager', () {
    late EventBus bus;
    late DeviceManager devMgr;
    late ConnectionManager connMgr;

    setUp(() async {
      bus = EventBus();
      devMgr = DeviceManager(
        eventBus: bus,
        myDeviceId: 'self',
        timeout: const Duration(seconds: 10),
      );
      connMgr = ConnectionManager(
        eventBus: bus,
        deviceManager: devMgr,
        grace: const Duration(milliseconds: 50),
      );
      await connMgr.start();
    });

    tearDown(() async {
      await connMgr.stop();
      await devMgr.dispose();
      bus.dispose();
    });

    test('DeviceFoundEvent 后 isOnline 为 true 且发射 DeviceOnlineEvent', () async {
      final online = <String>[];
      final sub = bus.watch<DeviceOnlineEvent>().listen((e) => online.add(e.deviceId));

      bus.emit(const DeviceFoundEvent(deviceId: 'remote-1', alias: 'A'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(connMgr.isOnline('remote-1'), isTrue);
      expect(connMgr.getQuality('remote-1'), ConnectionQuality.online);
      expect(online, contains('remote-1'));

      await sub.cancel();
    });

    test('DeviceLostEvent 后 isOnline 为 false 且发射 DeviceOfflineEvent', () async {
      final offline = <String>[];
      final sub = bus.watch<DeviceOfflineEvent>().listen((e) => offline.add(e.deviceId));

      bus.emit(const DeviceFoundEvent(deviceId: 'remote-1', alias: 'A'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      bus.emit(const DeviceLostEvent(deviceId: 'remote-1'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(connMgr.isOnline('remote-1'), isFalse);
      expect(offline, contains('remote-1'));

      await sub.cancel();
    });

    test('markReconnecting 发射 DeviceReconnectingEvent', () async {
      final reconnecting = <String>[];
      final sub = bus.watch<DeviceReconnectingEvent>().listen((e) => reconnecting.add(e.deviceId));

      // 通过 DeviceManager 添加设备，确保 Device 对象存在
      devMgr.onDatagram(deviceId: 'remote-1', ip: '192.168.1.1', port: 53317);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      connMgr.markReconnecting('remote-1');
      await Future<void>.delayed(Duration.zero);

      expect(connMgr.getQuality('remote-1'), ConnectionQuality.degraded);
      expect(reconnecting, contains('remote-1'));

      await sub.cancel();
    });
  });
}
