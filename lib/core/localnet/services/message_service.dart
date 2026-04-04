import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../models/localnet_device.dart';
import '../models/localnet_message.dart';
import 'debug_log_service.dart';

class MessageService {
  static const int apiPort = 53317;

  final String deviceId;
  final String deviceAlias;
  final _messagesController = StreamController<List<LocalnetMessage>>.broadcast();
  final List<LocalnetMessage> _messages = [];
  HttpServer? _server;

  MessageService({
    required this.deviceId,
    required this.deviceAlias,
  });

  Stream<List<LocalnetMessage>> get messagesStream => _messagesController.stream;
  List<LocalnetMessage> get messages => List.unmodifiable(_messages);

  Future<void> startServer() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, apiPort);
      debugLog.i('Message', '✓ HTTP 服务器已启动，端口 $apiPort');

      await for (final request in _server!) {
        _handleRequest(request);
      }
    } catch (e) {
      debugLog.e('Message', '✗ HTTP 服务器启动失败: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      debugLog.d('Message', '← HTTP 请求: ${request.method} $path (来自 ${request.connectionInfo?.remoteAddress.address})');

      if (path == '/api/localsend/v1/info' || path == '/api/localsend/v2/info') {
        // Device info
        final info = {
          'id': deviceId,
          'alias': deviceAlias,
          'port': apiPort,
          'deviceType': 'desktop',
          'version': '1.0',
        };
        request.response.write(jsonEncode(info));
        request.response.close();
        debugLog.d('Message', '→ 响应 /info: ${jsonEncode(info)}');
      } else if (path == '/api/localsend/v1/register' || path == '/api/localsend/v2/register') {
        // Register response
        request.response.write(jsonEncode({'status': 'ok'}));
        request.response.close();
        debugLog.d('Message', '→ 响应 /register: {"status":"ok"}');
      } else if (path == '/api/localsend/v1/message' || path == '/api/localsend/v2/message') {
        // Message
        final bodyBytes = await request.fold<List<int>>(
          [],
          (prev, element) => prev..addAll(element),
        );
        final body = utf8.decode(bodyBytes);
        debugLog.d('Message', '收到消息数据: $body');

        try {
          final json = jsonDecode(body) as Map<String, dynamic>;

          final message = LocalnetMessage(
            id: json['id'] as String? ?? const Uuid().v4(),
            senderId: json['senderId'] as String? ?? 'unknown',
            senderAlias: json['senderAlias'] as String? ?? 'Unknown',
            content: json['content'] as String? ?? '',
            timestamp: json['timestamp'] != null
                ? DateTime.parse(json['timestamp'] as String)
                : DateTime.now(),
          );

          _messages.add(message);
          _messagesController.add(_messages);
          debugLog.i('Message', '收到消息: ${message.senderAlias}: ${message.content}');

          request.response.write(jsonEncode({'status': 'ok'}));
          request.response.close();
        } catch (e) {
          debugLog.w('Message', '解析消息失败: $e');
          request.response.statusCode = HttpStatus.badRequest;
          request.response.close();
        }
      } else {
        debugLog.w('Message', '未知路径: $path');
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      }
    } catch (e) {
      debugLog.e('Message', '请求处理错误: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.close();
    }
  }

  Future<bool> sendMessage(LocalnetDevice target, String content) async {
    debugLog.i('Message', '发送消息到 ${target.alias} (${target.ip}:${target.port})');

    try {
      final message = LocalnetMessage(
        id: const Uuid().v4(),
        senderId: deviceId,
        senderAlias: deviceAlias,
        content: content,
        timestamp: DateTime.now(),
      );

      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://${target.ip}:${target.port}/api/localsend/v1/message'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(message.toJson()));

      debugLog.d('Message', '发送数据: ${jsonEncode(message.toJson())}');

      final response = await request.close();
      await response.drain<void>();
      client.close();

      if (response.statusCode == 200) {
        _messages.add(message);
        _messagesController.add(_messages);
        debugLog.i('Message', '✓ 消息发送成功');
        return true;
      }
      debugLog.w('Message', '✗ 消息发送失败，状态码: ${response.statusCode}');
      return false;
    } catch (e) {
      debugLog.e('Message', '✗ 消息发送失败: $e');
      return false;
    }
  }

  void stop() {
    debugLog.i('Message', '停止 HTTP 服务器');
    _server?.close();
    _server = null;
  }

  void dispose() {
    stop();
    _messagesController.close();
  }
}
