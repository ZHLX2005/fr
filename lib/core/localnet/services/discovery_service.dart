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

  final List<_SocketEntry> _sockets = [];
  final _devicesController = StreamController<List<LocalnetDevice>>.broadcast();
  final Map<String, LocalnetDevice> _devices = {};
  Timer? _cleanupTimer;
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
      // Get all network interfaces
      final interfaces = await NetworkInterface.list();

      for (final interface in interfaces) {
        // Skip loopback
        if (interface.name == 'lo' || interface.name == 'loopback') continue;

        for (final addr in interface.addresses) {
          // Only use IPv4
          if (addr.type != InternetAddressType.IPv4) continue;

          try {
            final socket = await RawDatagramSocket.bind(addr, 0, reuseAddress: true, reusePort: true);
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

            _logger('[Localnet] Bound socket on ${addr.address} for multicast');
          } catch (e) {
            _logger('[Localnet] Failed to bind on ${addr.address}: $e');
          }
        }
      }

      if (_sockets.isEmpty) {
        _logger('[Localnet] No sockets bound, trying fallback');
        // Fallback: bind to any
        try {
          final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0, reuseAddress: true);
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
        } catch (e) {
          _logger('[Localnet] Fallback also failed: $e');
        }
      }

      _startAnnouncing();
      _startCleanup();

      _logger('[Localnet] Discovery started with ${_sockets.length} sockets');
    } catch (e) {
      _logger('[Localnet] Discovery failed: $e');
      _isListening = false;
    }
  }

  void _startAnnouncing() {
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
    if (_sockets.isEmpty) return;

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

      for (final entry in _sockets) {
        try {
          entry.socket.send(data, InternetAddress(multicastGroup), multicastPort);
        } catch (e) {
          _logger('[Localnet] Send failed on ${entry.address}: $e');
        }
      }
    } catch (e) {
      _logger('[Localnet] Announce error: $e');
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

      // Send register response via HTTP if this is an announcement
      if (json['announce'] == true || json['announcement'] == true) {
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
    _cleanupTimer?.cancel();
    for (final entry in _sockets) {
      entry.socket.close();
    }
    _sockets.clear();
    _isListening = false;
    _devices.clear();
    _logger('[Localnet] Discovery stopped');
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
