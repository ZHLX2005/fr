import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../models/localnet_device.dart';
import '../models/localnet_message.dart';
import 'debug_log_service.dart';

/// 设备发现服务 - 基于 any_share 简化版协议
///
/// 协议格式:
/// - UDP 广播: "deviceId,port" (纯文本，逗号分隔)
/// - HTTP: POST /join 带上设备信息
///
/// 发现流程:
/// 1. 启动时广播自己的 "deviceId,port"
/// 2. 收到对方广播 → HTTP POST /join 到对方
/// 3. 对方响应 → 加入设备列表
class DiscoveryService {
  // UDP 多播配置
  static const String multicastAddress = '224.0.0.167';
  static const int multicastPort = 53317;

  // HTTP 端口（复用多播端口）
  static const int httpPort = 53317;

  /// 状态
  static const String stateInit = 'INIT';
  static const String stateStarting = 'STARTING';
  static const String stateRunning = 'RUNNING';
  static const String stateError = 'ERROR';

  final String deviceId;
  String deviceAlias = 'Flutter Device';
  int devicePort = httpPort;
  final String deviceModel = 'Flutter';
  final DeviceType deviceType = DeviceType.desktop;

  RawDatagramSocket? _udpSocket;
  HttpServer? _httpServer;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;
  final Map<String, LocalnetDevice> _devices = {};
  String _serviceState = stateInit;

  final _devicesController = StreamController<List<LocalnetDevice>>.broadcast();

  // 消息回调
  void Function(LocalnetMessage)? onMessageReceived;

  Stream<List<LocalnetDevice>> get devicesStream => _devicesController.stream;
  List<LocalnetDevice> get devices => _devices.values.toList();
  String get serviceState => _serviceState;

  /// 各组件运行状态
  bool get isUdpBroadcastRunning => _broadcastTimer != null && _broadcastTimer!.isActive;
  bool get isUdpListenerRunning => _udpSocket != null;
  bool get isHttpServerRunning => _httpServer != null;

  DiscoveryService() : deviceId = const Uuid().v4();

  void _logState(String from, String to, {String? note}) {
    debugLog.logState('Discovery', from, to, note: note);
  }

  /// 启动完整发现服务（向后兼容）
  Future<void> startListening() async {
    if (_serviceState == stateRunning) return;

    _logState(_serviceState, stateStarting, note: '启动发现服务');
    _serviceState = stateStarting;

    try {
      await startHttpServer();
      await startUdpListener();
      _startBroadcasting();
      _startCleanup();

      _logState(_serviceState, stateRunning, note: '服务已启动');
      _serviceState = stateRunning;

      debugLog.i('Discovery', '✓ 发现服务已启动');
      debugLog.i('Discovery', '  设备ID: ${deviceId.substring(0, 8)}...');
      debugLog.i('Discovery', '  设备别名: $deviceAlias');
      debugLog.i('Discovery', '  多播地址: $multicastAddress:$multicastPort');
      debugLog.i('Discovery', '  HTTP 端口: $httpPort');
    } catch (e) {
      debugLog.e('Discovery', '✗ 启动失败: $e');
      _logState(_serviceState, stateError, note: '启动失败: $e');
      _serviceState = stateError;
    }
  }

  /// 启动 HTTP 服务器
  Future<void> startHttpServer() async {
    if (_httpServer != null) return;
    await _startHttpServerInternal();
  }

  /// 停止 HTTP 服务器
  void stopHttpServer() {
    _httpServer?.close();
    _httpServer = null;
    debugLog.i('Discovery', 'HTTP 服务器已停止');
  }

  /// 启动 UDP 监听
  Future<void> startUdpListener() async {
    if (_udpSocket != null) return;
    await _startUdpListenerInternal();
  }

  /// 停止 UDP 监听
  void stopUdpListener() {
    _udpSocket?.close();
    _udpSocket = null;
    debugLog.i('Discovery', 'UDP 监听已停止');
  }

  /// 启动 UDP 广播
  void startUdpBroadcast() {
    if (_broadcastTimer != null && _broadcastTimer!.isActive) return;
    _startBroadcasting();
  }

  /// 停止 UDP 广播
  void stopUdpBroadcast() {
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    debugLog.i('Discovery', 'UDP 广播已停止');
  }

  /// 启动清理定时器
  void startCleanupTimer() {
    if (_cleanupTimer != null) return;
    _startCleanup();
  }

  /// 启动 HTTP 服务器，响应 /join 请求
  Future<void> _startHttpServerInternal() async {
    try {
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, httpPort);
      debugLog.i('Discovery', '✓ HTTP 服务器绑定成功 :$httpPort');

      _httpServer!.listen((request) async {
        final remoteIp = request.connectionInfo?.remoteAddress.address ?? 'unknown';
        final path = request.uri.path;

        debugLog.d('Discovery', '← HTTP ${request.method} $path (from $remoteIp)');

        if (path == '/join') {
          // any_share 风格的 join 请求
          try {
            final bodyBytes = await request.fold<List<int>>(
              [],
              (prev, element) => prev..addAll(element),
            );
            final body = utf8.decode(bodyBytes);
            debugLog.d('Discovery', '  Join 请求体: $body');

            // 解析 body (格式: deviceId=xxx&name=xxx&port=xxx)
            final params = Uri.splitQueryString(body);
            final senderId = params['deviceId'] ?? '';
            final senderName = params['name'] ?? 'Unknown';
            final senderPort = int.tryParse(params['port'] ?? '0') ?? httpPort;

            if (senderId.isNotEmpty && senderId != deviceId) {
              _addDevice(senderId, senderName, remoteIp, senderPort);
              debugLog.i('Discovery', '✓ 设备加入: $senderName ($remoteIp:$senderPort)');
            }

            // 响应 OK
            request.response.write('OK');
            request.response.close();
          } catch (e) {
            debugLog.w('Discovery', '  解析 join 请求失败: $e');
            request.response.statusCode = 400;
            request.response.close();
          }
        } else if (path == '/info') {
          // 本机信息
          final info = {
            'deviceId': deviceId,
            'name': deviceAlias,
            'port': devicePort.toString(),
            'type': deviceType.name,
          };
          request.response.write(Uri(queryParameters: info).query);
          request.response.close();
        } else if (path == '/message') {
          // 处理收到的消息
          try {
            final bodyBytes = await request.fold<List<int>>(
              [],
              (prev, element) => prev..addAll(element),
            );
            final body = utf8.decode(bodyBytes);
            debugLog.d('Discovery', '  消息体: $body');

            final json = jsonDecode(body) as Map<String, dynamic>;
            final message = LocalnetMessage.fromJson(json);

            // 忽略自己发送的消息
            if (message.senderId != deviceId) {
              onMessageReceived?.call(message);
              debugLog.i('Discovery', '✓ 收到消息 from ${message.senderAlias}: ${message.content}');
            }

            request.response.write('OK');
            request.response.close();
          } catch (e) {
            debugLog.w('Discovery', '  消息解析失败: $e');
            request.response.statusCode = 400;
            request.response.close();
          }
        } else {
          request.response.statusCode = 404;
          request.response.close();
        }
      });
    } catch (e) {
      debugLog.e('Discovery', '✗ HTTP 服务器启动失败: $e');
      rethrow;
    }
  }

  /// 启动 UDP 监听
  Future<void> _startUdpListenerInternal() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        multicastPort,
        reuseAddress: true,
        reusePort: true,
      );

      _udpSocket!.joinMulticast(InternetAddress(multicastAddress));

      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            _handleUdpDatagram(datagram);
          }
        }
      });

      debugLog.i('Discovery', '✓ UDP 监听成功 :$multicastPort');
    } catch (e) {
      debugLog.e('Discovery', '✗ UDP 监听失败: $e');
      rethrow;
    }
  }

  /// 处理收到的 UDP 数据报
  void _handleUdpDatagram(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final senderIp = datagram.address.address;

      debugLog.d('Discovery', '★ UDP 收到: "$message" (from $senderIp)');

      // 解析 "deviceId,port" 格式
      final parts = message.split(',');
      if (parts.length < 2) {
        debugLog.w('Discovery', '  格式错误: $message');
        return;
      }

      final senderId = parts[0].trim();
      final senderPort = int.tryParse(parts[1].trim()) ?? httpPort;

      // 忽略自己
      if (senderId == deviceId) {
        debugLog.d('Discovery', '  忽略自己');
        return;
      }

      // 添加到设备列表
      _addDevice(senderId, 'Unknown', senderIp, senderPort);

      // 发送 HTTP join 请求
      _sendHttpJoin(senderIp, senderPort);
    } catch (e) {
      debugLog.w('Discovery', '  UDP 解析失败: $e');
    }
  }

  /// 添加设备
  void _addDevice(String id, String alias, String ip, int port) {
    final now = DateTime.now();
    final existing = _devices[id];

    _devices[id] = LocalnetDevice(
      id: id,
      alias: existing?.alias ?? alias,
      ip: ip,
      port: port,
      deviceType: deviceType,
      version: '1.0',
      lastSeen: now,
    );

    _devicesController.add(_devices.values.toList());
  }

  /// 发送 HTTP join 请求
  Future<void> _sendHttpJoin(String targetIp, int targetPort) async {
    try {
      final body = 'deviceId=$deviceId&name=$deviceAlias&port=$devicePort';
      debugLog.d('Discovery', '→ HTTP POST /join to $targetIp:$targetPort');

      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://$targetIp:$targetPort/join'),
      );
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      request.write(body);

      final response = await request.close();
      await response.drain<void>();
      client.close();

      debugLog.d('Discovery', '← HTTP /join 响应: ${response.statusCode}');
    } catch (e) {
      debugLog.w('Discovery', '✗ HTTP /join 失败: $e');
    }
  }

  /// 开始定时广播
  void _startBroadcasting() {
    // 立即广播一次
    _sendBroadcast();

    // 每 3 秒广播一次
    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendBroadcast();
    });
  }

  /// 发送广播
  void _sendBroadcast() {
    if (_udpSocket == null) return;

    try {
      // "deviceId,port" 简单格式
      final message = '$deviceId,$devicePort';
      final data = utf8.encode(message);

      final sent = _udpSocket!.send(
        data,
        InternetAddress(multicastAddress),
        multicastPort,
      );

      if (sent > 0) {
        debugLog.d('Discovery', '→ UDP 广播: "$message" ($sent bytes)');
      }
    } catch (e) {
      debugLog.w('Discovery', '✗ UDP 广播失败: $e');
    }
  }

  /// 启动清理定时器
  void _startCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStaleDevices();
    });
  }

  /// 清理离线设备
  void _cleanupStaleDevices() {
    final now = DateTime.now();
    bool changed = false;

    _devices.removeWhere((key, device) {
      final isStale = now.difference(device.lastSeen) > const Duration(seconds: 15);
      if (isStale) {
        debugLog.i('Discovery', '设备离线: ${device.alias}');
        changed = true;
      }
      return isStale;
    });

    if (changed) {
      _devicesController.add(_devices.values.toList());
    }
  }

  /// 停止服务
  void stop() {
    if (_serviceState == stateInit) return;

    debugLog.i('Discovery', '停止发现服务...');

    stopUdpBroadcast();
    _cleanupTimer?.cancel();
    stopUdpListener();
    stopHttpServer();

    _devices.clear();
    _logState(_serviceState, stateInit, note: '服务已停止');
    _serviceState = stateInit;

    debugLog.i('Discovery', '发现服务已停止');
  }

  void dispose() {
    stop();
    _devicesController.close();
  }

  void updateAlias(String newAlias) {
    debugLog.i('Discovery', '设备别名: $deviceAlias → $newAlias');
    deviceAlias = newAlias;
  }

  void updatePort(int newPort) {
    debugLog.i('Discovery', '端口: $devicePort → $newPort');
    devicePort = newPort;
  }
}
