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
  static const String protocolVersion = '2.1';

  final String deviceId = const Uuid().v4();
  String deviceAlias = 'Flutter Device';
  final int devicePort = 53317;
  final String deviceModel = 'Flutter';
  final DeviceType deviceType = DeviceType.desktop;

  final List<_SocketEntry> _sockets = [];
  final _devicesController = StreamController<List<LocalnetDevice>>.broadcast();
  final Map<String, LocalnetDevice> _devices = {};
  Timer? _cleanupTimer;
  Timer? _httpScanTimer;
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

      bool bound = false;
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
            // Bind to anyIPv4 with port 0 (let system assign)
            final socket = await RawDatagramSocket.bind(
              InternetAddress.anyIPv4,
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
                  _handleDatagram(datagram, addr.address);
                }
              }
            });

            debugLog.i('Discovery', '✓ 绑定 socket 到 ${addr.address} 用于多播');
            bound = true;
          } catch (e) {
            debugLog.w('Discovery', '✗ 在 ${addr.address} 绑定失败: $e');
          }
        }
      }

      if (!bound) {
        debugLog.w('Discovery', '没有绑定到任何 socket，尝试备用方案');
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
                _handleDatagram(datagram, 'any');
              }
            }
          });
          debugLog.i('Discovery', '✓ 备用方案绑定成功');
        } catch (e) {
          debugLog.e('Discovery', '✗ 备用方案也失败了: $e');
        }
      }

      _startAnnouncing();
      _startHttpScanner();
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

  void _startHttpScanner() {
    debugLog.i('Discovery', '启动 HTTP 子网扫描...');
    // Initial scan after 2 seconds
    Future.delayed(const Duration(seconds: 2), _scanSubnet);
    // Then scan every 10 seconds
    _httpScanTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _scanSubnet();
    });
  }

  void _startCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStaleDevices();
    });
  }

  Future<void> _scanSubnet() async {
    // Get local IP to determine subnet
    final localIp = await getLocalIp();
    if (localIp == null) {
      debugLog.w('Discovery', '无法获取本机 IP');
      return;
    }

    // Extract subnet prefix
    final parts = localIp.split('.');
    if (parts.length != 4) return;
    final subnetPrefix = '${parts[0]}.${parts[1]}.${parts[2]}';

    debugLog.i('Discovery', 'HTTP 扫描子网 $subnetPrefix.0/24');

    int found = 0;

    // Scan subnet with limited concurrency
    final futures = <Future>[];
    for (int i = 1; i < 256; i++) {
      if (i.toString() == parts[3]) continue; // Skip self

      final targetIp = '$subnetPrefix.$i';
      futures.add(_httpScan(targetIp).then((device) {
        if (device != null) {
          found++;
        }
      }));

      // Limit concurrency
      if (futures.length >= 50) {
        await Future.wait(futures);
        futures.clear();
      }
    }

    await Future.wait(futures);

    if (found > 0) {
      debugLog.i('Discovery', 'HTTP 扫描发现 $found 个设备');
    }
  }

  Future<LocalnetDevice?> _httpScan(String ip) async {
    try {
      // Try v2 first, then v1
      for (final version in ['v2', 'v1']) {
        final url = 'http://$ip:$devicePort/api/localsend/$version/info?fingerprint=$deviceId';
        final client = HttpClient();
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set('Content-Type', 'application/json');

        final response = await request.close();
        await response.drain<void>();
        client.close();

        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;

          final fingerprint = json['fingerprint'] as String?;
          if (fingerprint == null || fingerprint == deviceId) {
            continue;
          }

          final device = LocalnetDevice(
            id: fingerprint,
            alias: json['alias'] as String? ?? 'Unknown',
            ip: ip,
            port: json['port'] as int? ?? devicePort,
            deviceType: _parseDeviceType(json['deviceType'] as String?),
            version: json['version'] as String? ?? protocolVersion,
            lastSeen: DateTime.now(),
          );

          _devices[fingerprint] = device;
          debugLog.i('Discovery', '✓ HTTP 发现设备: ${device.alias} ($ip)');
          _notifyDevices();
          return device;
        }
      }
    } catch (e) {
      // Silently ignore - many IPs won't have a LocalSend server
    }
    return null;
  }

  DeviceType _parseDeviceType(String? type) {
    switch (type) {
      case 'mobile':
        return DeviceType.mobile;
      case 'web':
        return DeviceType.web;
      default:
        return DeviceType.desktop;
    }
  }

  Future<void> _sendAnnouncement() async {
    if (_sockets.isEmpty) {
      debugLog.w('Discovery', '没有可用的 socket 发送广播');
      return;
    }

    try {
      final dto = {
        'alias': deviceAlias,
        'version': protocolVersion,
        'deviceModel': deviceModel,
        'deviceType': deviceType.name,
        'fingerprint': deviceId,
        'port': devicePort,
        'protocol': 'http',
        'download': false,
        'announce': true,
        'announcement': true,
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
            debugLog.d('Discovery', '→ UDP 广播已发送 (via ${entry.address.address})');
          }
        } catch (e) {
          debugLog.w('Discovery', '→ UDP 广播发送失败 (via ${entry.address.address}): $e');
        }
      }

      if (successCount > 0) {
        debugLog.i('Discovery', '✓ UDP 广播成功 (发送 $successCount/${_sockets.length} 个 socket)');
      } else {
        debugLog.e('Discovery', '✗ UDP 广播全部失败');
      }
    } catch (e) {
      debugLog.e('Discovery', '广播错误: $e');
    }
  }

  void _handleDatagram(Datagram datagram, String localAddr) {
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
      final device = LocalnetDevice(
        id: fingerprint,
        alias: json['alias'] as String? ?? 'Unknown',
        ip: ip,
        port: json['port'] as int? ?? devicePort,
        deviceType: _parseDeviceType(json['deviceType'] as String?),
        version: json['version'] as String? ?? protocolVersion,
        lastSeen: DateTime.now(),
      );

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
        'version': protocolVersion,
        'deviceModel': deviceModel,
        'deviceType': deviceType.name,
        'fingerprint': deviceId,
        'port': devicePort,
        'protocol': 'http',
        'download': false,
      };

      debugLog.d('Discovery', 'Register 请求: $dto');

      final client = HttpClient();

      // Try v2 first
      try {
        final request = await client.postUrl(
          Uri.parse('http://$ip:$port/api/localsend/v2/register'),
        );
        request.headers.set('Content-Type', 'application/json');
        request.write(jsonEncode(dto));

        final response = await request.close();
        await response.drain<void>();

        debugLog.i('Discovery', '✓ Register 响应已发送 v2 (状态码: ${response.statusCode})');
        client.close();
        return;
      } catch (e) {
        // Fallback to v1
      }

      final request = await client.postUrl(
        Uri.parse('http://$ip:$port/api/localsend/v1/register'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(dto));

      final response = await request.close();
      await response.drain<void>();
      client.close();

      debugLog.i('Discovery', '✓ Register 响应已发送 v1 (状态码: ${response.statusCode})');
    } catch (e) {
      debugLog.w('Discovery', '✗ Register 响应发送失败: $e');
    }
  }

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
    _httpScanTimer?.cancel();
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
