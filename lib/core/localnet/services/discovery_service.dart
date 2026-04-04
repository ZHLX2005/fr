import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/localnet_device.dart';
import 'debug_log_service.dart';

class DiscoveryService {
  static const String multicastGroup = '224.0.0.167';
  static const int multicastPort = 53317;

  final String deviceId = const Uuid().v4();
  String deviceAlias = 'Flutter Device';
  final int devicePort = 53317;
  final String deviceModel = 'Flutter';
  final DeviceType deviceType = DeviceType.desktop;

  final List<_SocketEntry> _sockets = [];
  final _devicesController = StreamController<List<LocalnetDevice>>.broadcast();
  final Map<String, LocalnetDevice> _devices = {};
  Timer? _cleanupTimer;
  bool _isListening = false;

  final NetworkInfo _networkInfo = NetworkInfo();

  Stream<List<LocalnetDevice>> get devicesStream => _devicesController.stream;
  List<LocalnetDevice> get devices => _devices.values.toList();
  bool get isListening => _isListening;

  Future<void> startListening() async {
    if (_isListening) return;
    _isListening = true;

    debugLog.i('Discovery', '=== 开始启动发现服务 ===');
    debugLog.i('Discovery', '设备ID: $deviceId');
    debugLog.i('Discovery', '设备别名: $deviceAlias');
    debugLog.i('Discovery', '多播地址: $multicastGroup:$multicastPort');

    try {
      // Get all network interfaces
      final interfaces = await NetworkInterface.list();
      debugLog.i('Discovery', '发现 ${interfaces.length} 个网络接口');

      for (final interface in interfaces) {
        // Skip loopback
        if (interface.name == 'lo' || interface.name == 'loopback') continue;

        debugLog.d('Discovery', '接口: ${interface.name}');
        for (final addr in interface.addresses) {
          debugLog.d('Discovery', '  地址: ${addr.address} (${addr.type})');
        }

        for (final addr in interface.addresses) {
          // Only use IPv4
          if (addr.type != InternetAddressType.IPv4) continue;

          try {
            final socket = await RawDatagramSocket.bind(
              addr,
              0,
              reuseAddress: true,
              reusePort: true,
            );
            socket.joinMulticast(InternetAddress(multicastGroup));

            _sockets.add(_SocketEntry(socket, addr));

            // Listen on this socket
            socket.listen((event) {
              if (event == RawSocketEvent.read) {
                final datagram = socket.receive();
                if (datagram != null) {
                  _handleDatagram(datagram);
                }
              }
            });

            debugLog.i('Discovery', '✓ 绑定 socket 到 ${addr.address} 用于多播');
          } catch (e) {
            debugLog.w('Discovery', '✗ 在 ${addr.address} 绑定失败: $e');
          }
        }
      }

      if (_sockets.isEmpty) {
        debugLog.w('Discovery', '没有绑定到任何 socket，尝试备用方案');
        // Fallback: bind to any
        try {
          final socket = await RawDatagramSocket.bind(
            InternetAddress.anyIPv4,
            0,
            reuseAddress: true,
          );
          socket.joinMulticast(InternetAddress(multicastGroup));
          _sockets.add(_SocketEntry(socket, InternetAddress.anyIPv4));
          socket.listen((event) {
            if (event == RawSocketEvent.read) {
              final datagram = socket.receive();
              if (datagram != null) {
                _handleDatagram(datagram);
              }
            }
          });
          debugLog.i('Discovery', '✓ 备用方案绑定成功');
        } catch (e) {
          debugLog.e('Discovery', '✗ 备用方案也失败了: $e');
        }
      }

      _startAnnouncing();
      _startCleanup();

      debugLog.i('Discovery', '=== 发现服务启动完成 ===');
      debugLog.i('Discovery', '当前绑定 ${_sockets.length} 个 socket');
    } catch (e) {
      debugLog.e('Discovery', '发现服务启动失败: $e');
      _isListening = false;
    }
  }

  void _startAnnouncing() {
    debugLog.i('Discovery', '开始广播 announcement...');
    _sendAnnouncement();
    Timer.periodic(const Duration(seconds: 3), (_) {
      _sendAnnouncement();
    });
  }

  void _startCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStaleDevices();
    });
  }

  Future<void> _sendAnnouncement() async {
    if (_sockets.isEmpty) {
      debugLog.w('Discovery', '没有可用的 socket 发送广播');
      return;
    }

    try {
      final dto = {
        'alias': deviceAlias,
        'version': '1.0',
        'deviceType': deviceType.name,
        'fingerprint': deviceId,
        'port': devicePort,
        'announce': true,
        'announcement': true, // v1 compatibility
      };

      final data = utf8.encode(jsonEncode(dto));
      debugLog.d('Discovery', '广播数据: ${utf8.decode(data)}');

      int successCount = 0;
      for (final entry in _sockets) {
        try {
          final sent = entry.socket.send(
            data,
            InternetAddress(multicastGroup),
            multicastPort,
          );
          if (sent > 0) {
            successCount++;
            debugLog.d('Discovery', '→ UDP 广播已发送 (${entry.address.address})');
          }
        } catch (e) {
          debugLog.w('Discovery', '→ UDP 广播发送失败 (${entry.address.address}): $e');
        }
      }

      if (successCount > 0) {
        debugLog.i('Discovery', '✓ UDP 广播成功 (发送 ${successCount}/${_sockets.length} 个 socket)');
      } else {
        debugLog.e('Discovery', '✗ UDP 广播全部失败');
      }
    } catch (e) {
      debugLog.e('Discovery', '广播错误: $e');
    }
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json is! Map<String, dynamic>) return;

      debugLog.d('Discovery', '收到 UDP 数据: $json');

      final fingerprint = json['fingerprint'] as String?;
      if (fingerprint == null || fingerprint == deviceId) {
        debugLog.d('Discovery', '忽略自己或无效的广播');
        return;
      }

      final ip = datagram.address.address;
      final device = LocalnetDevice.fromMulticast(json, ip);

      _devices[fingerprint] = device;
      debugLog.i('Discovery', '发现设备: ${device.alias} ($ip)');
      _notifyDevices();

      // Send register response via HTTP if this is an announcement
      if (json['announce'] == true || json['announcement'] == true) {
        debugLog.d('Discovery', '收到 announcement，发送 register 响应到 $ip:${device.port}');
        _sendRegisterResponse(ip, device.port);
      }
    } catch (e) {
      debugLog.w('Discovery', '解析数据错误: $e');
    }
  }

  Future<void> _sendRegisterResponse(String ip, int port) async {
    try {
      final dto = {
        'alias': deviceAlias,
        'version': '1.0',
        'deviceType': deviceType.name,
        'fingerprint': deviceId,
        'port': devicePort,
      };

      debugLog.d('Discovery', 'Register 请求: $dto');

      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://$ip:$port/api/localsend/v1/register'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(dto));

      final response = await request.close();
      await response.drain<void>();
      client.close();

      debugLog.i('Discovery', '✓ Register 响应已发送 (状态码: ${response.statusCode})');
    } catch (e) {
      debugLog.w('Discovery', '✗ Register 响应发送失败: $e');
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    bool changed = false;

    _devices.removeWhere((key, device) {
      final isStale = now.difference(device.lastSeen) > const Duration(seconds: 10);
      if (isStale) {
        debugLog.i('Discovery', '设备离线: ${device.alias}');
        changed = true;
      }
      return isStale;
    });

    if (changed) _notifyDevices();
  }

  void _notifyDevices() {
    _devicesController.add(_devices.values.toList());
  }

  Future<String?> getLocalIp() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (e) {
      return null;
    }
  }

  void stop() {
    debugLog.i('Discovery', '停止发现服务...');
    _cleanupTimer?.cancel();
    for (final entry in _sockets) {
      entry.socket.close();
    }
    _sockets.clear();
    _isListening = false;
    _devices.clear();
    debugLog.i('Discovery', '发现服务已停止');
  }

  void dispose() {
    stop();
    _devicesController.close();
  }
}

class _SocketEntry {
  final RawDatagramSocket socket;
  final InternetAddress address;

  _SocketEntry(this.socket, this.address);
}
