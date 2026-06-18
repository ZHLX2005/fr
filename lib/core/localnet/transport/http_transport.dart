import 'dart:async';
import 'dart:io';

import 'transport.dart';

/// HTTP 处理器签名
typedef HttpHandler = Future<void> Function(HttpRequest request);

/// HTTP 传输（Server + Client）
class HttpTransport extends Transport {
  HttpTransport({required super.config});

  HttpServer? _server;
  final Map<String, HttpHandler> _handlers = {};

  bool _isRunning = false;
  @override
  bool get isRunning => _isRunning;

  /// 实际绑定的端口（如果配置为 0 则由系统分配）
  int? get actualPort => _server?.port;

  /// 注册 HTTP 路径处理器
  void registerHandler(String path, HttpHandler handler) {
    _handlers[path] = handler;
  }

  /// 注销 HTTP 路径处理器
  void unregisterHandler(String path) {
    _handlers.remove(path);
  }

  @override
  Future<void> start() async {
    if (_isRunning) return;
    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      config.httpPort,
      shared: true,
    );

    _server!.listen(_handleRequest, cancelOnError: false);
    _isRunning = true;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    var handler = _handlers[path];

    // 未精确匹配时，尝试前缀匹配（如 /channel 匹配 /channel/chat）
    if (handler == null) {
      for (final entry in _handlers.entries) {
        if (path.startsWith(entry.key)) {
          handler = entry.value;
          break;
        }
      }
    }

    if (handler != null) {
      try {
        await handler(request);
      } catch (e) {
        // 如果 handler 未设置响应状态码和内容，返回 500
        if (request.response.statusCode == HttpStatus.ok) {
          request.response.statusCode = HttpStatus.internalServerError;
        }
        try {
          await request.response.close();
        } catch (_) {
          // response 已关闭则忽略
        }
      }
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  @override
  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    _isRunning = false;
  }
}
