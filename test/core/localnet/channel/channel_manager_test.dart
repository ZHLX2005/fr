import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/channel_manager.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/channel_message.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device_manager.dart';
import 'package:xiaodouzi_fr/core/localnet/event_bus/event_bus.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/http_transport.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';

void main() {
  group('ChannelManager', () {
    late HttpTransport transport;
    late EventBus bus;
    late DeviceManager deviceMgr;
    late ChannelManager mgr;
    final localConfig = TransportConfig(httpPort: 0);

    setUp(() async {
      transport = HttpTransport(config: localConfig);
      await transport.start();
      bus = EventBus();
      deviceMgr = DeviceManager(
        eventBus: bus,
        myDeviceId: 'self',
        timeout: const Duration(seconds: 10),
      );
      mgr = ChannelManager(
        eventBus: bus,
        deviceManager: deviceMgr,
        transport: transport,
      );
      await mgr.start();
    });

    tearDown(() async {
      await mgr.stop();
      await transport.stop();
      bus.dispose();
    });

    test('通过 /channel/<name> 收到的消息能进入 watchChannel', () async {
      final received = <ChannelMessage>[];
      final sub = mgr.watchChannel('chat').listen(received.add);

      // 模拟另一台设备发请求
      final localPortActual = transport.actualPort!;
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$localPortActual/channel/chat'));
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode({
        'senderId': 'remote-1',
        'channel': 'chat',
        'payload': {'text': 'hello'},
        'timestamp': DateTime.now().toIso8601String(),
      }));
      final resp = await req.close();
      await resp.drain<void>();
      client.close();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received.length, 1);
      expect(received.first.sourceDeviceId, 'remote-1');
      expect(received.first.payload['text'], 'hello');

      await sub.cancel();
    });

    test('sendTo 通过设备 ip:port 发送通道消息', () async {
      // 启动第二个 HttpTransport 模拟对端
      final remoteConfig = TransportConfig(httpPort: 0);
      final remoteTransport = HttpTransport(config: remoteConfig);
      await remoteTransport.start();
      final remotePort = remoteTransport.actualPort!;

      // 模拟收到端点注册到本机 DeviceManager
      deviceMgr.onDatagram(
        deviceId: 'remote-1',
        ip: '127.0.0.1',
        port: remotePort,
      );

      // 对端注册 handler
      final received = <Map<String, dynamic>>[];
      remoteTransport.registerHandler('/channel/chat', (req) async {
        final body = await utf8.decodeStream(req);
        received.add(jsonDecode(body) as Map<String, dynamic>);
        req.response.statusCode = 200;
        await req.response.close();
      });

      // 发送
      final result = await mgr.sendTo(
        'remote-1',
        'chat',
        {'text': 'hi'},
      );
      expect(result.success, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received.length, 1);
      expect(received.first['senderId'], 'self');
      expect((received.first['payload'] as Map)['text'], 'hi');

      await remoteTransport.stop();
    });
  });
}
