import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../models/localnet_device.dart';
import '../models/localnet_message.dart';
import 'debug_log_service.dart';

class MessageService {
  static const int defaultPort = 53317;

  /// 状态机状态
  static const String stateInit = 'INIT';
  static const String stateStarting = 'STARTING';
  static const String stateRunning = 'RUNNING';
  static const String stateError = 'ERROR';

  final String deviceId;
  String deviceAlias;
  int apiPort = defaultPort;

  final _messagesController = StreamController<List<LocalnetMessage>>.broadcast();
  final List<LocalnetMessage> _messages = [];
  HttpServer? _server;
  String _serviceState = stateInit;

  MessageService({
    required this.deviceId,
    required this.deviceAlias,
  });

  Stream<List<LocalnetMessage>> get messagesStream => _messagesController.stream;
  List<LocalnetMessage> get messages => List.unmodifiable(_messages);
  String get serviceState => _serviceState;

  void _logState(String from, String to, {String? note}) {
    debugLog.logState('Message', from, to, note: note);
  }

  Future<void> startServer() async {
    if (_server != null) return;

    _logState(_serviceState, stateStarting, note: '启动 HTTP 服务器');
    _serviceState = stateStarting;
    debugLog.i('Message', '正在启动 HTTP 服务器...');

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, apiPort);
      _logState(_serviceState, stateRunning, note: 'HTTP 服务器已启动 :$apiPort');
      _serviceState = stateRunning;
      debugLog.i('Message', '✓ HTTP 服务器已启动，端口 $apiPort');
      debugLog.i('Message', '  监听地址: ${InternetAddress.anyIPv4.address}:$apiPort');

      await for (final request in _server!) {
        _handleRequest(request);
      }
    } catch (e) {
      debugLog.e('Message', '✗ HTTP 服务器启动失败: $e');
      _logState(_serviceState, stateError, note: '启动失败: $e');
      _serviceState = stateError;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;
      final remoteIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';
      debugLog.d('Message', '← HTTP 请求: ${request.method} $path (来自 $remoteIp)');

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
        debugLog.i('Message', '✓ 收到 /register 请求，来自 $remoteIp');
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
    if (_server == null) return;

    _logState(_serviceState, stateInit, note: '停止 HTTP 服务器');
    debugLog.i('Message', '停止 HTTP 服务器');
    _server?.close();
    _server = null;
    _serviceState = stateInit;
  }

  void dispose() {
    stop();
    _messagesController.close();
  }

  void updateAlias(String newAlias) {
    debugLog.i('Message', '设备别名更新: $deviceAlias → $newAlias');
    deviceAlias = newAlias;
  }

  void updatePort(int newPort) {
    debugLog.i('Message', '端口更新: $apiPort → $newPort');
    apiPort = newPort;
  }
}
