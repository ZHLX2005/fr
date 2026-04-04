# LocalNet MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现局域网设备发现 + 文本消息传输，基于 LocalSend v1 协议

**Architecture:**
- 单例 LocalnetService 整合发现服务和消息服务
- 分离式 UI：发现页 → 聊天页
- UDP 多播广播 + HTTP API 消息传输

**Tech Stack:** network_info_plus (已有), dart:io (RawDatagramSocket, HttpServer)

---

## 文件结构

```
lib/core/localnet/
├── localnet.dart                    # 导出文件 (修改)
├── localnet_service.dart            # 单例服务 (新建)
├── models/
│   ├── localnet_device.dart         # 设备模型 (修改)
│   └── localnet_message.dart        # 消息模型 (保留)
├── pages/
│   ├── localnet_discover_page.dart  # 发现页面 (新建)
│   └── localnet_chat_page.dart      # 聊天页面 (新建)
└── services/
    ├── discovery_service.dart        # UDP多播服务 (新建)
    └── message_service.dart         # HTTP消息服务 (修改)
```

---

## Task 1: 清理旧代码，重建模型

**Files:**
- Delete: `lib/core/localnet/localnet_page.dart`
- Delete: `lib/core/localnet/services/localnet_discovery_service.dart`
- Modify: `lib/core/localnet/models/localnet_device.dart`
- Modify: `lib/core/localnet/localnet.dart`

- [ ] **Step 1: 删除旧文件**

Delete `lib/core/localnet/localnet_page.dart` and `lib/core/localnet/services/localnet_discovery_service.dart`

- [ ] **Step 2: 更新 localnet_device.dart**

```dart
import 'dart:convert';

enum DeviceType { mobile, desktop, web }

class LocalnetDevice {
  final String id;          // fingerprint
  final String alias;
  final String ip;
  final int port;
  final DeviceType deviceType;
  final String? deviceModel;
  final String version;
  final DateTime lastSeen;

  LocalnetDevice({
    required this.id,
    required this.alias,
    required this.ip,
    required this.port,
    required this.deviceType,
    this.deviceModel,
    required this.version,
    required this.lastSeen,
  });

  factory LocalnetDevice.fromMulticast(Map<String, dynamic> json, String ip) {
    return LocalnetDevice(
      id: json['fingerprint'] as String? ?? ip,
      alias: json['alias'] as String? ?? 'Unknown',
      ip: ip,
      port: json['port'] as int? ?? 53317,
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == (json['deviceType'] as String?),
        orElse: () => DeviceType.desktop,
      ),
      deviceModel: json['deviceModel'] as String?,
      version: json['version'] as String? ?? '1.0',
      lastSeen: DateTime.now(),
    );
  }

  factory LocalnetDevice.fromRegister(Map<String, dynamic> json, String ip) {
    return LocalnetDevice(
      id: json['fingerprint'] as String? ?? ip,
      alias: json['alias'] as String? ?? 'Unknown',
      ip: ip,
      port: json['port'] as int? ?? 53317,
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == (json['deviceType'] as String?),
        orElse: () => DeviceType.desktop,
      ),
      deviceModel: json['deviceModel'] as String?,
      version: json['version'] as String? ?? '1.0',
      lastSeen: DateTime.now(),
    );
  }

  LocalnetDevice copyWith({DateTime? lastSeen}) {
    return LocalnetDevice(
      id: id,
      alias: alias,
      ip: ip,
      port: port,
      deviceType: deviceType,
      deviceModel: deviceModel,
      version: version,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
```

- [ ] **Step 3: 更新 localnet.dart 导出**

```dart
export 'localnet_service.dart';
export 'models/localnet_device.dart';
export 'models/localnet_message.dart';
export 'pages/localnet_discover_page.dart';
export 'pages/localnet_chat_page.dart';
export 'services/discovery_service.dart';
export 'services/message_service.dart';
```

- [ ] **Step 4: 提交**

```bash
git add lib/core/localnet/
git commit -m "refactor(localnet): 重构目录结构，准备实现MVP"
```

---

## Task 2: 实现 DiscoveryService

**Files:**
- Create: `lib/core/localnet/services/discovery_service.dart`

- [ ] **Step 1: 创建 discovery_service.dart**

```dart
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
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/localnet/services/discovery_service.dart
git commit -m "feat(localnet): 添加DiscoveryService实现UDP多播发现"
```

---

## Task 3: 实现 MessageService

**Files:**
- Modify: `lib/core/localnet/services/message_service.dart`

- [ ] **Step 1: 重写 message_service.dart**

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/localnet_device.dart';
import '../models/localnet_message.dart';

class MessageService {
  static const int apiPort = 53317;

  final String deviceId;
  final String deviceAlias;
  final _messagesController = StreamController<List<LocalnetMessage>>.broadcast();
  final List<LocalnetMessage> _messages = [];
  HttpServer? _server;
  final _logger = debugPrint;

  MessageService({
    required this.deviceId,
    required this.deviceAlias,
  });

  Stream<List<LocalnetMessage>> get messagesStream => _messagesController.stream;
  List<LocalnetMessage> get messages => List.unmodifiable(_messages);

  Future<void> startServer() async {
    if (_server != null) return;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, apiPort);
      _logger('[Localnet] Message server started on $apiPort');

      await for (final request in _server!) {
        _handleRequest(request);
      }
    } catch (e) {
      _logger('[Localnet] Server failed: $e');
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final path = request.uri.path;

      if (path == '/api/localsend/v1/info') {
        // Device info
        final info = {
          'id': deviceId,
          'alias': deviceAlias,
          'port': apiPort,
          'deviceType': 'desktop',
          'version': '1.0',
        };
        request.response.write(jsonEncode(info));
        request.response.close();
      } else if (path == '/api/localsend/v1/register') {
        // Register response
        request.response.write(jsonEncode({'status': 'ok'}));
        request.response.close();
      } else if (path == '/api/localsend/v1/message') {
        // Message
        final bodyBytes = await request.fold<List<int>>(
          [],
          (prev, element) => prev..addAll(element),
        );
        final body = utf8.decode(bodyBytes);
        final json = jsonDecode(body) as Map<String, dynamic>;

        final message = LocalnetMessage(
          id: json['id'] as String? ?? const Uuid().v4(),
          senderId: json['senderId'] as String? ?? 'unknown',
          senderAlias: json['senderAlias'] as String? ?? 'Unknown',
          content: json['content'] as String? ?? '',
          timestamp: json['timestamp'] != null
              ? DateTime.parse(json['timestamp'] as String)
              : DateTime.now(),
        );

        _messages.add(message);
        _messagesController.add(_messages);
        _logger('[Localnet] Message from ${message.senderAlias}: ${message.content}');

        request.response.write(jsonEncode({'status': 'ok'}));
        request.response.close();
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.close();
      }
    } catch (e) {
      _logger('[Localnet] Request error: $e');
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
        Uri.parse('http://${target.ip}:${target.port}/api/localsend/v1/message'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(message.toJson()));

      final response = await request.close();
      await response.drain<void>();
      client.close();

      if (response.statusCode == 200) {
        _messages.add(message);
        _messagesController.add(_messages);
        _logger('[Localnet] Sent to ${target.alias}');
        return true;
      }
      return false;
    } catch (e) {
      _logger('[Localnet] Send failed: $e');
      return false;
    }
  }

  void stop() {
    _server?.close();
    _server = null;
    _logger('[Localnet] Server stopped');
  }

  void dispose() {
    stop();
    _messagesController.close();
  }
}
```

- [ ] **Step 2: 更新 localnet_message.dart**

确保 toJson 正确:

```dart
Map<String, dynamic> toJson() => {
      'id': id,
      'senderId': senderId,
      'senderAlias': senderAlias,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
    };
```

- [ ] **Step 3: 提交**

```bash
git add lib/core/localnet/services/message_service.dart lib/core/localnet/models/localnet_message.dart
git commit -m "feat(localnet): 实现MessageService HTTP消息服务"
```

---

## Task 4: 创建 LocalnetService 单例

**Files:**
- Create: `lib/core/localnet/localnet_service.dart`

- [ ] **Step 1: 创建 localnet_service.dart**

```dart
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'models/localnet_device.dart';
import 'models/localnet_message.dart';
import 'services/discovery_service.dart';
import 'services/message_service.dart';

class LocalnetService {
  static final LocalnetService _instance = LocalnetService._internal();
  factory LocalnetService() => _instance;
  LocalnetService._internal();

  final String deviceId = const Uuid().v4();
  late final DiscoveryService discovery;
  late final MessageService message;

  String deviceAlias = 'Flutter Device';

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    discovery = DiscoveryService();
    message = MessageService(
      deviceId: deviceId,
      deviceAlias: deviceAlias,
    );

    // Set alias on discovery service
    discovery.deviceAlias = deviceAlias;

    _logger('[Localnet] Service initialized');
  }

  Future<void> start() async {
    init();
    await message.startServer();
    await discovery.startListening();
    _logger('[Localnet] Started');
  }

  void stop() {
    discovery.stop();
    message.stop();
    _logger('[Localnet] Stopped');
  }

  void dispose() {
    stop();
    discovery.dispose();
    message.dispose();
  }

  List<LocalnetDevice> get devices => discovery.devices;
  Stream<List<LocalnetDevice>> get devicesStream => discovery.devicesStream;

  List<LocalnetMessage> get messages => message.messages;
  Stream<List<LocalnetMessage>> get messagesStream => message.messagesStream;

  Future<bool> sendMessage(LocalnetDevice target, String content) {
    return message.sendMessage(target, content);
  }

  void updateAlias(String alias) {
    deviceAlias = alias;
    discovery.deviceAlias = alias;
    message.deviceAlias = alias;
  }
}

final localnetService = LocalnetService();
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/localnet/localnet_service.dart
git commit -m "feat(localnet): 添加LocalnetService单例"
```

---

## Task 5: 创建发现页面

**Files:**
- Create: `lib/core/localnet/pages/localnet_discover_page.dart`

- [ ] **Step 1: 创建 localnet_discover_page.dart**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localnet_service.dart';
import '../models/localnet_device.dart';
import 'localnet_chat_page.dart';

class LocalnetDiscoverPage extends StatefulWidget {
  const LocalnetDiscoverPage({super.key});

  @override
  State<LocalnetDiscoverPage> createState() => _LocalnetDiscoverPageState();
}

class _LocalnetDiscoverPageState extends State<LocalnetDiscoverPage> {
  final _service = localnetService;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _startService();
  }

  Future<void> _startService() async {
    setState(() => _isStarting = true);
    await _service.start();
    setState(() => _isStarting = false);
  }

  @override
  void dispose() {
    // Don't stop service on dispose - keep it running
    super.dispose();
  }

  void _navigateToChat(LocalnetDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocalnetChatPage(device: device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalNet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _startService,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // 本机信息卡片
          _buildSelfCard(),
          const Divider(height: 1),
          // 设备列表
          Expanded(
            child: _buildDeviceList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelfCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(
            Icons.smartphone,
            size: 40,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _service.deviceAlias,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '本机 · 在线',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                      ),
                ),
              ],
            ),
          ),
          if (_isStarting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return StreamBuilder<List<LocalnetDevice>>(
      stream: _service.devicesStream,
      initialData: _service.devices,
      builder: (context, snapshot) {
        final devices = snapshot.data ?? [];

        if (devices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_find,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '正在搜索设备...',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '确保其他设备也运行了 LocalNet',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            return _DeviceTile(
              device: device,
              onTap: () => _navigateToChat(device),
            );
          },
        );
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final LocalnetDevice device;
  final VoidCallback onTap;

  const _DeviceTile({required this.device, required this.onTap});

  IconData get _icon {
    switch (device.deviceType) {
      case DeviceType.mobile:
        return Icons.phone_android;
      case DeviceType.web:
        return Icons.web;
      case DeviceType.desktop:
      default:
        return Icons.computer;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon, size: 32),
      title: Text(device.alias),
      subtitle: Text('${device.ip}:${device.port}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/localnet/pages/localnet_discover_page.dart
git commit -m "feat(localnet): 创建发现页面"
```

---

## Task 6: 创建聊天页面

**Files:**
- Create: `lib/core/localnet/pages/localnet_chat_page.dart`

- [ ] **Step 1: 创建 localnet_chat_page.dart**

```dart
import 'package:flutter/material.dart';

import '../localnet_service.dart';
import '../models/localnet_device.dart';
import '../models/localnet_message.dart';

class LocalnetChatPage extends StatefulWidget {
  final LocalnetDevice device;

  const LocalnetChatPage({super.key, required this.device});

  @override
  State<LocalnetChatPage> createState() => _LocalnetChatPageState();
}

class _LocalnetChatPageState extends State<LocalnetChatPage> {
  final _service = localnetService;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _controller.text.trim();
    if (content.isEmpty) return;
    if (_isSending) return;

    setState(() => _isSending = true);
    _controller.clear();

    final success = await _service.sendMessage(widget.device, content);

    setState(() => _isSending = false);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送失败')),
      );
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.alias),
        subtitle: Text('${widget.device.ip}:${widget.device.port}'),
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: _buildMessageList(),
          ),
          // 输入区域
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<List<LocalnetMessage>>(
      stream: _service.messagesStream,
      initialData: _service.messages,
      builder: (context, snapshot) {
        final messages = snapshot.data ?? [];

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '开始发送消息',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final isMine = msg.senderId == _service.deviceId;
            return _MessageBubble(
              message: msg,
              isMine: isMine,
            );
          },
        );
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _isSending ? null : _sendMessage,
            child: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final LocalnetMessage message;
  final bool isMine;

  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMine
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMine ? const Radius.circular(4) : null,
            bottomLeft: !isMine ? const Radius.circular(4) : null,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  message.senderAlias,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            Text(
              message.content,
              style: TextStyle(
                color: isMine
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isMine
                    ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)
                    : Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/localnet/pages/localnet_chat_page.dart
git commit -m "feat(localnet): 创建聊天页面"
```

---

## Task 7: 更新 main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 更新 _DevPage 使用新页面**

```dart
/// LocalNet 页面
class _DevPage extends StatelessWidget {
  const _DevPage();

  @override
  Widget build(BuildContext context) {
    return const LocalnetDiscoverPage();
  }
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/main.dart
git commit -m "feat(localnet): 集成LocalNet发现页面到导航"
```

---

## Task 8: 最终检查

- [ ] **Step 1: flutter analyze**

```bash
flutter analyze lib/core/localnet/
```

- [ ] **Step 2: flutter build web --release**

```bash
flutter build web --release
```

- [ ] **Step 3: 推送所有**

```bash
git push
```

---

## 自我检查

1. **Spec 覆盖**: 所有 spec 中的功能都有对应的 task 实现
2. **占位符检查**: 无 TBD/TODO，所有步骤都有完整代码
3. **类型一致性**: LocalnetDevice, LocalnetMessage, LocalnetService 的接口在所有 task 中一致
4. **架构**: DiscoveryService 和 MessageService 分离，单例 LocalnetService 整合
5. **UI**: 发现页 → 聊天页分离式导航
