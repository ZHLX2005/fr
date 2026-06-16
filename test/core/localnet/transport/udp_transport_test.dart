import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/udp_transport.dart';

void main() {
  group('UdpTransport', () {
    test('start 后能发送并收到自己的多播数据', () async {
      // 使用非 239 段地址避免与生产端口冲突
      final config = TransportConfig(
        multicastAddress: '239.255.255.250',
        multicastPort: 5679, // 与生产端口错开
      );
      final transport = UdpTransport(config: config);

      final received = <String>[];
      final completer = Completer<void>();
      late StreamSubscription sub;

      sub = transport.datagrams.listen((dg) {
        final text = utf8.decode(dg.data);
        received.add(text);
        if (!completer.isCompleted) completer.complete();
      });

      await transport.start();
      transport.send('test-device-1', 53317);

      // 等最多 2 秒
      await completer.future.timeout(const Duration(seconds: 2));
      await sub.cancel();
      await transport.stop();

      expect(received, isNotEmpty);
      expect(received.first, contains('test-device-1'));
    });

    test('未 start 时 send 应抛出', () async {
      final config = TransportConfig(multicastPort: 5680);
      final transport = UdpTransport(config: config);
      expect(
        () => transport.send('id', 53317),
        throwsA(isA<StateError>()),
      );
    });

    test('stop 后 isRunning 为 false', () async {
      final config = TransportConfig(multicastPort: 5681);
      final transport = UdpTransport(config: config);
      await transport.start();
      expect(transport.isRunning, isTrue);
      await transport.stop();
      expect(transport.isRunning, isFalse);
    });
  });
}
