import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/localnet_discovery_service.dart';
import 'services/localnet_message_service.dart';

class LocalnetPage extends StatefulWidget {
  const LocalnetPage({super.key});

  @override
  State<LocalnetPage> createState() => _LocalnetPageState();
}

class _LocalnetPageState extends State<LocalnetPage> {
  late final LocalnetDiscoveryService _discoveryService;
  late final LocalnetMessageService _messageService;

  final String _deviceId = const Uuid().v4();
  final String _deviceAlias = 'Flutter Device';

  List<LocalnetDevice> _devices = [];
  List<LocalnetMessage> _messages = [];
  LocalnetDevice? _selectedDevice;
  final _messageController = TextEditingController();

  StreamSubscription<List<LocalnetDevice>>? _devicesSub;
  StreamSubscription<List<LocalnetMessage>>? _messagesSub;

  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  void _initServices() {
    _discoveryService = LocalnetDiscoveryService();
    _messageService = LocalnetMessageService(
      deviceId: _deviceId,
      deviceAlias: _deviceAlias,
    );

    // Start message server
    _messageService.startServer();

    // Listen to device discoveries
    _devicesSub = _discoveryService.devicesStream.listen((devices) {
      setState(() {
        _devices = devices;
      });
    });

    // Listen to incoming messages
    _messagesSub = _messageService.messagesStream.listen((messages) {
      setState(() {
        _messages = messages;
      });
    });

    // Start UDP multicast listening
    _discoveryService.startListening();
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _messagesSub?.cancel();
    _discoveryService.dispose();
    _messageService.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _scanSubnet() async {
    setState(() => _isScanning = true);
    final discovered = await _discoveryService.scanSubnet();
    setState(() {
      _devices = [..._devices, ...discovered];
      _isScanning = false;
    });
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    if (_selectedDevice != null) {
      final success = await _messageService.sendMessage(_selectedDevice!, content);
      if (success) {
        _messageController.clear();
      } else {
        _showSnackBar('Failed to send message');
      }
    } else {
      _showSnackBar('Select a device first');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalNet'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            onPressed: _isScanning ? null : _scanSubnet,
            tooltip: 'Scan Subnet',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _discoveryService.startListening(),
            tooltip: 'Restart Discovery',
          ),
        ],
      ),
      body: Row(
        children: [
          // Device List
          SizedBox(
            width: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Devices (${_devices.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: _devices.isEmpty
                      ? const Center(
                          child: Text(
                            'No devices found\nStart the app on other devices',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            final isSelected = _selectedDevice == device;
                            return ListTile(
                              selected: isSelected,
                              leading: Icon(
                                device.deviceType == DeviceType.mobile
                                    ? Icons.phone_android
                                    : Icons.computer,
                              ),
                              title: Text(device.alias),
                              subtitle: Text('${device.ip}:${device.port}'),
                              onTap: () {
                                setState(() {
                                  _selectedDevice = device;
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Chat Area
          Expanded(
            child: Column(
              children: [
                // Selected device info
                if (_selectedDevice != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Row(
                      children: [
                        Icon(
                          _selectedDevice!.deviceType == DeviceType.mobile
                              ? Icons.phone_android
                              : Icons.computer,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedDevice!.alias,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${_selectedDevice!.ip}:${_selectedDevice!.port}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 32),
                        SizedBox(width: 12),
                        Text('Select a device to send messages'),
                      ],
                    ),
                  ),
                // Messages
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMine = msg.senderId == _deviceId;
                            return Align(
                              alignment: isMine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isMine
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isMine)
                                      Text(
                                        msg.senderAlias,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    Text(msg.content),
                                    Text(
                                      _formatTime(msg.timestamp),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isMine
                                            ? Colors.white70
                                            : Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                // Input
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _selectedDevice != null ? _sendMessage : null,
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}
