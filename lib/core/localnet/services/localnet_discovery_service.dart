import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/localnet_device.dart';

class LocalnetDiscoveryService {
  static const String multicastGroup = '224.0.0.167';
  static const int multicastPort = 53317;

  final String deviceId = const Uuid().v4();
  final String deviceAlias = 'Flutter Device';
  final int devicePort = 53317;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  final _devicesController = StreamController<List<LocalnetDevice>>.broadcast();
  final Map<String, LocalnetDevice> _devices = {};
  Timer? _cleanupTimer;
  Timer? _announceTimer;
  bool _isListening = false;
  final _logger = debugPrint;

  Stream<List<LocalnetDevice>> get devicesStream => _devicesController.stream;
  List<LocalnetDevice> get devices => _devices.values.toList();

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

      // Start announcing periodically
      _startAnnouncing();

      // Cleanup stale devices every 10 seconds
      _cleanupTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _cleanupStaleDevices();
      });

      _logger('[Localnet] Started listening on UDP multicast');
    } catch (e) {
      _logger('[Localnet] Failed to start listening: $e');
      _isListening = false;
    }
  }

  void _startAnnouncing() {
    // Announce immediately
    _sendAnnouncement();

    // Then every 3 seconds
    _announceTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _sendAnnouncement();
    });
  }

  Future<void> _sendAnnouncement() async {
    if (_socket == null) return;

    try {
      final localIp = await _getLocalIp();
      final dto = {
        'alias': deviceAlias,
        'version': '1.0',
        'deviceType': 'desktop',
        'fingerprint': deviceId,
        'port': devicePort,
        'announce': true,
      };

      final data = utf8.encode(jsonEncode(dto));
      _socket!.send(
        data,
        InternetAddress(multicastGroup),
        multicastPort,
      );
      _logger('[Localnet] Sent announcement from $localIp');
    } catch (e) {
      _logger('[Localnet] Failed to send announcement: $e');
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

      final isNew = !_devices.containsKey(fingerprint);
      _devices[fingerprint] = device;

      if (isNew) {
        _logger('[Localnet] Discovered device: ${device.alias} ($ip)');
      }

      _notifyDevices();
    } catch (e) {
      _logger('[Localnet] Failed to parse datagram: $e');
    }
  }

  void _cleanupStaleDevices() {
    final now = DateTime.now();
    final staleThreshold = const Duration(seconds: 10);
    bool changed = false;

    _devices.removeWhere((key, device) {
      final isStale = now.difference(device.lastSeen) > staleThreshold;
      if (isStale) {
        _logger('[Localnet] Device went offline: ${device.alias}');
        changed = true;
      }
      return isStale;
    });

    if (changed) {
      _notifyDevices();
    }
  }

  void _notifyDevices() {
    _devicesController.add(_devices.values.toList());
  }

  Future<String?> _getLocalIp() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      return ip;
    } catch (e) {
      return null;
    }
  }

  /// Scan the local subnet for devices via HTTP
  Future<List<LocalnetDevice>> scanSubnet() async {
    final localIp = await _getLocalIp();
    if (localIp == null) return [];

    final baseIp = localIp.split('.').take(3).join('.');
    final discovered = <LocalnetDevice>[];

    // Scan in parallel batches
    final futures = <Future>[];
    for (int i = 1; i < 256; i++) {
      final ip = '$baseIp.$i';
      if (ip == localIp) continue;

      futures.add(_checkHttpDevice(ip, discovered));
    }

    await Future.wait(futures);
    return discovered;
  }

  Future<void> _checkHttpDevice(String ip, List<LocalnetDevice> discovered) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 500);

      final request = await client.getUrl(
        Uri.parse('http://$ip:$multicastPort/api/localsend/v1/info'),
      );
      request.headers.set('User-Agent', 'Localnet/1.0');

      final response = await request.close().timeout(const Duration(milliseconds: 500));
      await response.drain<void>();

      if (response.statusCode == 200) {
        // Try to read the response body
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        final device = LocalnetDevice.fromJson(json, ip);
        if (!_devices.containsKey(device.id)) {
          _devices[device.id] = device;
          discovered.add(device);
          _logger('[Localnet] HTTP discovered: ${device.alias} ($ip)');
          _notifyDevices();
        }
      }
      client.close();
    } catch (e) {
      // Silently ignore - device not available
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
    _logger('[Localnet] Stopped discovery');
  }

  void dispose() {
    stop();
    _devicesController.close();
  }
}
