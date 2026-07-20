import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../device/device_manager.dart';
import '../transport/http_transport.dart';
import '../transport/transport_frame.dart';
import 'transport_channel.dart';

/// LAN 后端的 TransportChannel — 封装现有 HTTP P2P 传输逻辑。
///
/// 每个 `(channelName, remoteDeviceId)` 对应一条 HTTP POST 请求；
/// 服务端路由 `/channel/<name>` 在打开通道时注册。
class LanChannel implements TransportChannel {
  LanChannel({
    required HttpTransport http,
    DeviceManager? deviceManager,
    String? myDeviceId,
  }) : _http = http,
       _deviceMgr = deviceManager,
       myDeviceId = myDeviceId ?? deviceManager?.myDeviceId ?? '';

  final HttpTransport _http;
  final DeviceManager? _deviceMgr;
  final String myDeviceId;
  final Map<String, StreamController<TransportFrame>> _watchers = {};
  final Map<String, String> _remoteDeviceIds = {};
  final Set<String> _registered = {};

  @override
  Future<void> open({
    required String channelName,
    required String remoteDeviceId,
  }) async {
    _remoteDeviceIds[channelName] = remoteDeviceId;
    if (_registered.add(channelName)) {
      _http.registerHandler(
        '/channel/$channelName',
        (request) => _handle(request, channelName),
      );
    }
  }

  @override
  Future<SendResult> send(String channelName, Uint8List data) async {
    final remoteDeviceId = _remoteDeviceIds[channelName];
    if (remoteDeviceId == null) {
      return SendResult.fail('channel not open');
    }
    final device = _deviceMgr?.getDevice(remoteDeviceId);
    if (device == null) {
      return SendResult.fail('device not found');
    }

    final url = 'http://${device.ip}:${device.port}/channel/$channelName';
    final body = jsonEncode({
      'senderId': myDeviceId,
      'payload': base64Encode(data),
      'timestamp': DateTime.now().toIso8601String(),
    });
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(body);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok
          ? SendResult.ok(statusCode: response.statusCode)
          : SendResult.fail('HTTP ${response.statusCode}');
    } catch (error) {
      return SendResult.fail('send exception: $error');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Stream<TransportFrame> watch(String channelName) {
    return _watchers
        .putIfAbsent(
          channelName,
          () => StreamController<TransportFrame>.broadcast(),
        )
        .stream;
  }

  @override
  Future<void> close() async {
    for (final channelName in _registered) {
      _http.unregisterHandler('/channel/$channelName');
    }
    _registered.clear();
    _remoteDeviceIds.clear();
    for (final controller in _watchers.values) {
      await controller.close();
    }
    _watchers.clear();
  }

  Future<void> _handle(HttpRequest request, String channelName) async {
    try {
      final body = await utf8.decodeStream(request);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final frame = TransportFrame(
        channelName: channelName,
        sourceDeviceId: json['senderId'] as String? ?? 'unknown',
        payload: base64Decode(json['payload'] as String? ?? ''),
        timestamp:
            DateTime.tryParse(json['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );
      _watchers[channelName]?.add(frame);
      request.response.statusCode = HttpStatus.ok;
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
    } on TypeError {
      request.response.statusCode = HttpStatus.badRequest;
    } finally {
      await request.response.close();
    }
  }
}
