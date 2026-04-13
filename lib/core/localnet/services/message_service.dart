import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../models/localnet_constants.dart';
import '../models/localnet_device.dart';
import '../models/localnet_message.dart';
import 'debug_log_service.dart';

/// 消息服务 - 基于 HTTP POST 的简单消息传输
///
/// 协议:
/// - POST /message 发送消息 (HTTP client)
/// - 接收消息由 DiscoveryService 的 HTTP 服务器代理
class MessageService {
  static int get defaultPort => LocalnetConstants.defaultPort;

  static const String stateInit = 'INIT';
  static const String stateRunning = 'RUNNING';

  final String deviceId;
  String deviceAlias;
  int apiPort = defaultPort;

  final _messagesController =
      StreamController<List<LocalnetMessage>>.broadcast();
  final List<LocalnetMessage> _messages = [];
  String _serviceState = stateInit;

  MessageService({required this.deviceId, required this.deviceAlias});

  Stream<List<LocalnetMessage>> get messagesStream =>
      _messagesController.stream;
  List<LocalnetMessage> get messages => List.unmodifiable(_messages);
  String get serviceState => _serviceState;

  /// 添加收到的消息（由 DiscoveryService 调用）
  void addReceivedMessage(LocalnetMessage message) {
    _messages.add(message);
    _messagesController.add(List.unmodifiable(_messages));
  }

  /// 发送消息到目标设备
  Future<bool> sendMessage(LocalnetDevice target, String content) async {
    final message = LocalnetMessage(
      id: const Uuid().v4(),
      senderId: deviceId,
      senderAlias: deviceAlias,
      content: content,
      timestamp: DateTime.now(),
      type: MessageType.text,
    );

    try {
      final url = LocalnetConstants.buildHttpUrl(
        target.ip,
        target.port,
        LocalnetConstants.httpPathMessage,
      );
      debugLog.d('Message', '→ POST ${LocalnetConstants.httpPathMessage} to ${target.ip}:${target.port}');

      final client = HttpClient();
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(message.toJson()));

      final response = await request.close();
      await response.drain<void>();
      client.close();

      debugLog.d('Message', '← HTTP 响应: ${response.statusCode}');

      if (response.statusCode == 200) {
        // 也添加到本地消息列表（显示已发送）
        addReceivedMessage(message);
        return true;
      }
      return false;
    } catch (e) {
      debugLog.w('Message', '✗ 发送失败: $e');
      return false;
    }
  }

  /// 清空消息
  void clearMessages() {
    _messages.clear();
    _messagesController.add(List.unmodifiable(_messages));
  }

  void stop() {
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
}
