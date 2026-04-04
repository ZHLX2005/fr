import 'dart:async';
import 'dart:io';

import '../models/localnet_device.dart';
import '../models/localnet_message.dart';
import 'debug_log_service.dart';

/// 消息服务 - 第一阶段暂时不需要，保留基础结构
class MessageService {
  static const int defaultPort = 53317;

  static const String stateInit = 'INIT';
  static const String stateRunning = 'RUNNING';

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

  /// 启动服务器 - 发现阶段暂时不需要
  Future<void> startServer() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, apiPort);
      _serviceState = stateRunning;
      debugLog.i('Message', 'HTTP 服务器已启动 :$apiPort');

      await for (final request in _server!) {
        _handleRequest(request);
      }
    } catch (e) {
      debugLog.e('Message', 'HTTP 服务器启动失败: $e');
    }
  }

  void _handleRequest(HttpRequest request) {
    // 发现阶段暂时不处理任何请求
    request.response.statusCode = 404;
    request.response.close();
  }

  void stop() {
    _server?.close();
    _server = null;
    _serviceState = stateInit;
  }

  void dispose() {
    stop();
    _messagesController.close();
  }

  void updateAlias(String newAlias) {
    deviceAlias = newAlias;
  }

  void updatePort(int newPort) {
    apiPort = newPort;
  }

  Future<bool> sendMessage(LocalnetDevice target, String content) async {
    // 发现阶段暂不实现
    return false;
  }
}
