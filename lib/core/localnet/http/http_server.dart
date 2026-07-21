// lib/core/localnet/http/http_server.dart
//
// 轻量 HTTP Server — 每设备运行一个实例，用于可靠点对点通信。
// 接收 invite/accept/game-state 等请求，返回 HTTP 状态码作为 ACK。
//
// 用法：
// ```dart
// final server = LocalHttpServer(port: 53318);
// server.on('/api/v1/invite', (req, body) => handleInvite(body));
// await server.start();
// ```

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// HTTP 请求处理器
typedef HttpRequestHandler = Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> body);

/// 轻量 HTTP Server
class LocalHttpServer {
  LocalHttpServer({this.port = 53318});

  final int port;
  HttpServer? _server;
  final _routes = <String, HttpRequestHandler>{};
  bool _running = false;

  bool get isRunning => _running;

  /// 注册路由处理器
  void on(String path, HttpRequestHandler handler) {
    _routes[path] = handler;
  }

  /// 启动
  Future<void> start() async {
    if (_running) return;
    _server = await HttpServer.bind('0.0.0.0', port);
    _running = true;
    // ignore: unawaited_futures
    _server!.listen(_handleRequest);
  }

  /// 停止
  Future<void> stop() async {
    if (!_running) return;
    await _server?.close(force: true);
    _server = null;
    _running = false;
  }

  void _handleRequest(HttpRequest request) {
    // 只处理 POST，只处理 JSON
    if (request.method != 'POST') {
      request.response.statusCode = 405;
      request.response.close();
      return;
    }

    final path = request.uri.path;
    final handler = _routes[path];
    if (handler == null) {
      request.response.statusCode = 404;
      request.response.close();
      return;
    }

    // 异步处理：读 body → 调 handler → 回响应
    // ignore: unawaited_futures
    request.cast<List<int>>().transform(utf8.decoder).join().then((body) async {
      Map<String, dynamic> json;
      try {
        json = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        request.response.statusCode = 400;
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'invalid json'}));
        await request.response.close();
        return;
      }

      try {
        final result = await handler(json);
        if (result != null) {
          request.response.statusCode = 200;
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(result));
        } else {
          request.response.statusCode = 200;
        }
      } catch (e) {
        request.response.statusCode = 500;
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': e.toString()}));
      }
      await request.response.close();
    });
  }
}
