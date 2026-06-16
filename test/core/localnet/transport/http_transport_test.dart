import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/http_transport.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';

void main() {
  group('HttpTransport', () {
    test('start 后 isRunning 为 true', () async {
      final config = TransportConfig(httpPort: 0); // 让系统分配
      final transport = HttpTransport(config: config);
      await transport.start();
      expect(transport.isRunning, isTrue);
      await transport.stop();
    });

    test('注册的 /test 路由能收到 POST', () async {
      final config = TransportConfig(httpPort: 0);
      final transport = HttpTransport(config: config);

      final received = <String>[];
      transport.registerHandler('/test', (request) async {
        final body = await utf8.decodeStream(request);
        received.add(body);
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      });

      await transport.start();
      final port = transport.actualPort;
      expect(port, isNotNull);

      // 客户端发请求
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:$port/test'));
      req.write('hello');
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.ok);
      await resp.drain<void>();
      client.close();

      // 等待异步处理
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(received, contains('hello'));

      await transport.stop();
    });

    test('未注册的路径返回 404', () async {
      final config = TransportConfig(httpPort: 0);
      final transport = HttpTransport(config: config);
      await transport.start();
      final port = transport.actualPort!;

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/unknown'));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.notFound);
      client.close();

      await transport.stop();
    });
  });
}
