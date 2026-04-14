import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/localnet_device.dart';
import '../models/localnet_message.dart';

class LocalnetMessageService {
  static const int apiPort = 53317;

  final String deviceId;
  final String deviceAlias;
  final _messagesController =
      StreamController<List<LocalnetMessage>>.broadcast();
  final List<LocalnetMessage> _messages = [];
  HttpServer? _server;
  final _logger = debugPrint;

  LocalnetMessageService({required this.deviceId, required this.deviceAlias});

  Stream<List<LocalnetMessage>> get messagesStream =>
      _messagesController.stream;
  List<LocalnetMessage> get messages => List.unmodifiable(_messages);

  Future<void> startServer() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, apiPort);
      _logger('[Localnet] Message server started on port $apiPort');

      await for (final request in _server!) {
        _handleRequest(request);
      }
    } catch (e) {
      _logger('[Localnet] Failed to start message server: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      if (path == '/api/localsend/v1/info' ||
          path == '/api/localsend/v2/info') {
        // Device info endpoint
        final info = {
          'id': deviceId,
          'alias': deviceAlias,
          'port': apiPort,
          'deviceType': 'desktop',
          'version': '1.0',
        };
        request.response.write(jsonEncode(info));
        request.response.close();
      } else if (path == '/api/localsend/v1/message' ||
          path == '/api/localsend/v2/message') {
        // Message endpoint
        final bodyBytes = await request.fold<List<int>>(
          [],
          (prev, element) => prev..addAll(element),
        );
        final body = utf8.decode(bodyBytes);
        final json = jsonDecode(body) as Map<String, dynamic>;

        final message = LocalnetMessage.fromJson(json);
        _messages.add(message);
        _messagesController.add(_messages);

        _logger(
          '[Localnet] Received message from ${message.senderAlias}: ${message.content}',
        );

        request.response.write(jsonEncode({'status': 'ok'}));
        request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      }
    } catch (e) {
      _logger('[Localnet] Error handling request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.close();
    }
  }

  Future<bool> sendMessage(LocalnetDevice target, String content) async {
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
        Uri.parse(
          'http://${target.ip}:${target.port}/api/localsend/v1/message',
        ),
      );

      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(message.toJson()));

      final response = await request.close();
      await response.drain<void>();

      client.close();

      if (response.statusCode == 200) {
        _messages.add(message);
        _messagesController.add(_messages);
        _logger('[Localnet] Sent message to ${target.alias}');
        return true;
      }
      return false;
    } catch (e) {
      _logger('[Localnet] Failed to send message: $e');
      return false;
    }
  }

  Future<bool> sendMessageToIp(String ip, int port, String content) async {
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
        Uri.parse('http://$ip:$port/api/localsend/v1/message'),
      );

      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(message.toJson()));

      final response = await request.close();
      await response.drain<void>();

      client.close();

      if (response.statusCode == 200) {
        _messages.add(message);
        _messagesController.add(_messages);
        return true;
      }
      return false;
    } catch (e) {
      _logger('[Localnet] Failed to send message to $ip:$port: $e');
      return false;
    }
  }

  void stop() {
    _server?.close();
    _server = null;
    _logger('[Localnet] Message server stopped');
  }

  void dispose() {
    stop();
    _messagesController.close();
  }
}
