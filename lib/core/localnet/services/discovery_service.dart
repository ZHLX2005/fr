import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/localnet_device.dart';

class DiscoveryService {
  static const String multicastGroup = '224.0.0.167';
  static const int multicastPort = 53317;

  final String deviceId = const Uuid().v4();
  String deviceAlias = 'Flutter Device';
  final int devicePort = 53317;
  final String deviceModel = 'Flutter';
  final DeviceType deviceType = DeviceType.desktop;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  final _devicesController = StreamController<List<LocalnetDevice>>.broadcast();
  final Map<String, LocalnetDevice> _devices = {};
  Timer? _cleanupTimer;
  Timer? _announceTimer;
  bool _isListening = false;
  final _logger = debugPrint;

  final NetworkInfo _networkInfo = NetworkInfo();

  Stream<List<LocalnetDevice>> get devicesStream => _devicesController.stream;
  List<LocalnetDevice> get devices => _devices.values.toList();
  bool get isListening => _isListening;

  Future<void> startListening() async {
    if (_isListening) return;
    _isListening = true;

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );

      _socket!.joinMulticast(InternetAddress(multicastGroup));

      _subscription = _socket!.listen((event) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          _handleDatagram(datagram);
        }
      });

      _startAnnouncing();
      _startCleanup();

      _logger('[Localnet] Discovery started');
    } catch (e) {
      _logger('[Localnet] Discovery failed: $e');
      _isListening = false;
    }
  }

  void _startAnnouncing() {
    _sendAnnouncement();
    _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendAnnouncement();
    });
  }

  void _startCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _cleanupStaleDevices();
    });
  }

  Future<void> _sendAnnouncement() async {
    if (_socket == null) return;

    try {
      final dto = {
        'alias': deviceAlias,
        'version': '1.0',
        'deviceType': deviceType.name,
        'fingerprint': deviceId,
        'port': devicePort,
        'announce': true,
      };

      final data = utf8.encode(jsonEncode(dto));
      _socket!.send(data, InternetAddress(multicastGroup), multicastPort);
    } catch (e) {
      _logger('[Localnet] Announce failed: $e');
    }
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json is! Map<String, dynamic>) return;

      final fingerprint = json['fingerprint'] as String?;
      if (fingerprint == null || fingerprint == deviceId) return;

      final ip = datagram.address.address;
      final device = LocalnetDevice.fromMulticast(json, ip);

      _devices[fingerprint] = device;
      _logger('[Localnet] Found device: ${device.alias} ($ip)');
      _notifyDevices();

      // Send register response via HTTP
      if (json['announce'] == true) {
        _sendRegisterResponse(ip, device.port);
      }
    } catch (e) {
      _logger('[Localnet] Parse error: $e');
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

      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://$ip:$port/api/localsend/v1/register'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(dto));

      final response = await request.close();
      await response.drain<void>();
      client.close();

      _logger('[Localnet] Sent register to $ip:$port');
    } catch (e) {
      _logger('[Localnet] Register failed: $e');
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    bool changed = false;

    _devices.removeWhere((key, device) {
      final isStale = now.difference(device.lastSeen) > const Duration(seconds: 10);
      if (isStale) {
        _logger('[Localnet] Device offline: ${device.alias}');
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
    _subscription?.cancel();
    _announceTimer?.cancel();
    _socket?.close();
    _socket = null;
    _cleanupTimer?.cancel();
    _isListening = false;
    _devices.clear();
    _logger('[Localnet] Discovery stopped');
  }

  void dispose() {
    stop();
    _devicesController.close();
  }
}
