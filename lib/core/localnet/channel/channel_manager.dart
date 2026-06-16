import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../device/device_manager.dart';
import '../event_bus/event_bus.dart';
import '../event_bus/lan_event.dart';
import '../transport/http_transport.dart';
import 'channel_message.dart';
import 'send_result.dart';

/// 通道管理器
///
/// 职责：
/// 1. 注册 HTTP `/channel/<channel>` 路由
/// 2. 收到对端发来的通道消息 → 发射 ChannelMessageEvent + 推送到对应 channel 的 Stream
/// 3. 提供 sendTo API 按 deviceId 发送通道消息（内部查 ip:port → POST）
class ChannelManager {
  ChannelManager({
    required EventBus eventBus,
    required DeviceManager deviceManager,
    required HttpTransport transport,
  })  : _bus = eventBus,
        _deviceMgr = deviceManager,
        _transport = transport;

  final EventBus _bus;
  final DeviceManager _deviceMgr;
  final HttpTransport _transport;

  final Map<String, StreamController<ChannelMessage>> _channelControllers = {};
  bool _started = false;

  /// 订阅某个 channel 的消息
  Stream<ChannelMessage> watchChannel(String channel) {
    return _channelControllers
        .putIfAbsent(
          channel,
          () => StreamController<ChannelMessage>.broadcast(),
        )
        .stream;
  }

  /// 启动：注册路由
  Future<void> start() async {
    if (_started) return;
    // 注册一个通配 handler，根据 path 后缀分发
    _transport.registerHandler('/channel', _handleChannelRoot);
    _started = true;
  }

  /// 停止
  Future<void> stop() async {
    _transport.unregisterHandler('/channel');
    for (final c in _channelControllers.values) {
      await c.close();
    }
    _channelControllers.clear();
    _started = false;
  }

  /// 发送通道消息
  Future<SendResult> sendTo(
    String targetDeviceId,
    String channel,
    Map<String, dynamic> payload,
  ) async {
    final device = _deviceMgr.getDevice(targetDeviceId);
    if (device == null) {
      return SendResult.fail('设备不存在: $targetDeviceId');
    }

    final body = jsonEncode({
      'senderId': _deviceMgr.myDeviceId,
      'channel': channel,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final url = 'http://${device.ip}:${device.port}/channel/$channel';
    final sw = Stopwatch()..start();
    try {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse(url));
      req.headers.set('Content-Type', 'application/json');
      req.write(body);
      final resp = await req.close();
      await resp.drain<void>();
      client.close();
      sw.stop();

      if (resp.statusCode == 200) {
        return SendResult.ok(statusCode: resp.statusCode, latency: sw.elapsed);
      }
      return SendResult.fail(
        'HTTP ${resp.statusCode}',
        statusCode: resp.statusCode,
      );
    } catch (e) {
      sw.stop();
      return SendResult.fail('发送异常: $e');
    }
  }

  Future<void> _handleChannelRoot(HttpRequest request) async {
    // path 形如 /channel/chat → 提取 chat
    final path = request.uri.path;
    final channel = path.startsWith('/channel/')
        ? path.substring('/channel/'.length)
        : '';
    if (channel.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    try {
      final bodyStr = await utf8.decodeStream(request);
      final json = jsonDecode(bodyStr) as Map<String, dynamic>;

      final message = ChannelMessage(
        sourceDeviceId: json['senderId'] as String? ?? 'unknown',
        channel: channel,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
                DateTime.now(),
      );

      // 推送到订阅者
      _channelControllers[channel]?.add(message);
      // 同步发射全局事件
      _bus.emit(ChannelMessageEvent(
        sourceDeviceId: message.sourceDeviceId,
        channel: message.channel,
        payload: message.payload,
        timestamp: message.timestamp,
      ));

      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
    }
  }

  /// Test helper: Simulate receiving a message (for testing only)
  void testSimulateMessage(String channel, Map<String, dynamic> payload) {
    final message = ChannelMessage(
      sourceDeviceId: 'test-peer',
      channel: channel,
      payload: payload,
      timestamp: DateTime.now(),
    );
    _channelControllers[channel]?.add(message);
  }
}
