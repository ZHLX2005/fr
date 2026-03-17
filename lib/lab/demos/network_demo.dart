import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';
import '../lab_container.dart';

/// 网络测试 Demo
class NetworkDemo extends DemoPage {
  @override
  String get title => '网络测试';

  @override
  String get description => 'HTTP/WebSocket/蓝牙BLE测试工具';

  @override
  Widget buildPage(BuildContext context) {
    return const _NetworkDemoPage();
  }
}

class _NetworkDemoPage extends StatefulWidget {
  const _NetworkDemoPage();

  @override
  State<_NetworkDemoPage> createState() => _NetworkDemoPageState();
}

class _NetworkDemoPageState extends State<_NetworkDemoPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _httpUrlController = TextEditingController(text: 'https://jsonplaceholder.typicode.com/posts/1');
  final _httpMethodController = TextEditingController(text: 'GET');
  final _httpHeadersController = TextEditingController(text: 'Content-Type: application/json');
  final _httpBodyController = TextEditingController();
  final _wsUrlController = TextEditingController(text: 'wss://echo.websocket.org');
  final _wsMessageController = TextEditingController(text: 'Hello WebSocket');

  String _httpResult = '';
  bool _httpLoading = false;
  int _httpStatusCode = 0;
  Duration? _httpDuration;

  WebSocketChannel? _wsChannel;
  final List<String> _wsMessages = [];
  bool _wsConnected = false;
  String _wsConnectionStatus = '未连接';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _httpUrlController.dispose();
    _httpMethodController.dispose();
    _httpHeadersController.dispose();
    _httpBodyController.dispose();
    _wsUrlController.dispose();
    _wsMessageController.dispose();
    _wsChannel?.sink.close();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _bleMessageController.dispose();
    super.dispose();
  }

  // HTTP请求
  Future<void> _sendHttpRequest() async {
    setState(() {
      _httpLoading = true;
      _httpResult = '';
      _httpStatusCode = 0;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final uri = Uri.parse(_httpUrlController.text);
      final method = _httpMethodController.text.toUpperCase();

      // 解析headers
      final headers = <String, String>{};
      final headerLines = _httpHeadersController.text.split('\n');
      for (final line in headerLines) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          headers[parts[0].trim()] = parts.sublist(1).join(':').trim();
        }
      }

      // 发起请求
      final client = http.Client();
      http.Response response;

      if (method == 'GET') {
        response = await client.get(uri, headers: headers);
      } else if (method == 'POST') {
        response = await client.post(uri, headers: headers, body: _httpBodyController.text);
      } else if (method == 'PUT') {
        response = await client.put(uri, headers: headers, body: _httpBodyController.text);
      } else if (method == 'DELETE') {
        response = await client.delete(uri, headers: headers);
      } else if (method == 'PATCH') {
        response = await client.patch(uri, headers: headers, body: _httpBodyController.text);
      } else {
        response = await client.get(uri, headers: headers);
      }

      stopwatch.stop();

      setState(() {
        _httpStatusCode = response.statusCode;
        _httpDuration = stopwatch.elapsed;
        _httpResult = response.body;
        _httpLoading = false;
      });
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _httpStatusCode = 0;
        _httpDuration = stopwatch.elapsed;
        _httpResult = 'Error: $e';
        _httpLoading = false;
      });
    }
  }

  // WebSocket连接
  void _connectWebSocket() {
    try {
      final uri = Uri.parse(_wsUrlController.text);
      _wsChannel = WebSocketChannel.connect(uri);

      setState(() {
        _wsConnectionStatus = '连接中...';
      });

      _wsChannel!.ready.then((_) {
        setState(() {
          _wsConnected = true;
          _wsConnectionStatus = '已连接';
          _wsMessages.add('[${DateTime.now().toIso8601String().substring(11, 19)}] 连接成功');
        });
      }).catchError((e) {
        setState(() {
          _wsConnected = false;
          _wsConnectionStatus = '连接失败: $e';
        });
      });

      _wsChannel!.stream.listen((message) {
        setState(() {
          _wsMessages.add('[${DateTime.now().toIso8601String().substring(11, 19)}] 收到: $message');
        });
      }, onError: (error) {
        setState(() {
          _wsConnected = false;
          _wsConnectionStatus = '连接断开: $error';
        });
      }, onDone: () {
        setState(() {
          _wsConnected = false;
          _wsConnectionStatus = '连接已关闭';
        });
      });
    } catch (e) {
      setState(() {
        _wsConnectionStatus = '连接失败: $e';
      });
    }
  }

  // 发送WebSocket消息
  void _sendWebSocketMessage() {
    if (_wsChannel != null && _wsConnected) {
      final message = _wsMessageController.text;
      _wsChannel!.sink.add(message);
      setState(() {
        _wsMessages.add('[${DateTime.now().toIso8601String().substring(11, 19)}] 发送: $message');
      });
    }
  }

  // 断开WebSocket
  void _disconnectWebSocket() {
    _wsChannel?.sink.close();
    setState(() {
      _wsConnected = false;
      _wsConnectionStatus = '已断开';
      _wsMessages.add('[${DateTime.now().toIso8601String().substring(11, 19)}] 连接已断开');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'HTTP', icon: Icon(Icons.http)),
          Tab(text: 'WebSocket', icon: Icon(Icons.cable)),
          Tab(text: '蓝牙BLE', icon: Icon(Icons.bluetooth)),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHttpTab(),
          _buildWebSocketTab(),
          _buildBluetoothTab(),
        ],
      ),
    );
  }

  Widget _buildHttpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // URL输入
          TextField(
            controller: _httpUrlController,
            decoration: const InputDecoration(
              labelText: 'URL',
              border: OutlineInputBorder(),
              hintText: 'https://api.example.com/endpoint',
            ),
          ),
          const SizedBox(height: 12),
          // 方法和Headers
          Row(
            children: [
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _httpMethodController,
                  decoration: const InputDecoration(
                    labelText: 'Method',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _httpHeadersController,
                  decoration: const InputDecoration(
                    labelText: 'Headers (每行一个)',
                    border: OutlineInputBorder(),
                    hintText: 'Content-Type: application/json',
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 请求体
          TextField(
            controller: _httpBodyController,
            decoration: const InputDecoration(
              labelText: 'Request Body (JSON)',
              border: OutlineInputBorder(),
              hintText: '{"key": "value"}',
            ),
            maxLines: 4,
          ),
          const SizedBox(height: 16),
          // 发送按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _httpLoading ? null : _sendHttpRequest,
              icon: _httpLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_httpLoading ? '请求中...' : '发送请求'),
            ),
          ),
          const SizedBox(height: 16),
          // 响应结果
          if (_httpStatusCode > 0 || _httpResult.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _httpStatusCode >= 200 && _httpStatusCode < 300
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _httpStatusCode >= 200 && _httpStatusCode < 300
                      ? Colors.green
                      : Colors.red,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _httpStatusCode >= 200 && _httpStatusCode < 300
                        ? Icons.check_circle
                        : Icons.error,
                    color: _httpStatusCode >= 200 && _httpStatusCode < 300
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Status: $_httpStatusCode',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _httpStatusCode >= 200 && _httpStatusCode < 300
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  const Spacer(),
                  if (_httpDuration != null)
                    Text(
                      '${_httpDuration!.inMilliseconds}ms',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // 响应体
          if (_httpResult.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _httpResult,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.green,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebSocketTab() {
    return Column(
      children: [
        // 连接配置
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _wsUrlController,
                decoration: const InputDecoration(
                  labelText: 'WebSocket URL',
                  border: OutlineInputBorder(),
                  hintText: 'wss://example.com/ws',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _wsConnected ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _wsConnected ? Colors.green : Colors.red,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _wsConnected ? Icons.check_circle : Icons.cancel,
                            size: 16,
                            color: _wsConnected ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _wsConnectionStatus,
                            style: TextStyle(
                              color: _wsConnected ? Colors.green : Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (!_wsConnected)
                    ElevatedButton.icon(
                      onPressed: _connectWebSocket,
                      icon: const Icon(Icons.link),
                      label: const Text('连接'),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: _disconnectWebSocket,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      icon: const Icon(Icons.link_off),
                      label: const Text('断开'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // 发送消息
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wsMessageController,
                      decoration: const InputDecoration(
                        labelText: '发送消息',
                        border: OutlineInputBorder(),
                        hintText: '输入要发送的消息',
                      ),
                      enabled: _wsConnected,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _wsConnected ? _sendWebSocketMessage : null,
                    icon: const Icon(Icons.send),
                    label: const Text('发送'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 消息列表
        Expanded(
          child: _wsMessages.isEmpty
              ? Center(
                  child: Text(
                    '暂无消息',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _wsMessages.length,
                  itemBuilder: (context, index) {
                    final msg = _wsMessages[index];
                    final isSent = msg.contains('发送:');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSent
                            ? Colors.blue.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        msg,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: isSent ? Colors.blue : Colors.black87,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // 蓝牙相关状态
  List<ScanResult> _bleDevices = [];
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _selectedCharacteristic;
  bool _isScanning = false;
  bool _isConnected = false;
  final List<String> _bleLogs = [];
  final _bleMessageController = TextEditingController();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionEvent>? _connectionSubscription;
  StreamSubscription<List<int>>? _characteristicSubscription;

  Future<void> _startScan() async {
    setState(() {
      _bleDevices.clear();
      _isScanning = true;
      _bleLogs.add('[${_time()}] 开始扫描...');
    });

    // 请求蓝牙相关权限
    final permissions = [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];

    final statuses = await permissions.request();
    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);

    if (denied) {
      setState(() {
        _bleLogs.add('[${_time()}] 错误: 需要蓝牙和位置权限才能扫描');
        _bleLogs.add('[${_time()}] 请在设置中开启权限');
        _isScanning = false;
      });
      return;
    }

    // 检查蓝牙状态
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      setState(() {
        _bleLogs.add('[${_time()}] 错误: 蓝牙未开启');
        _isScanning = false;
      });
      return;
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _bleDevices = results;
      });
    });

    // 5秒后自动停止
    Future.delayed(const Duration(seconds: 5), () {
      if (_isScanning) {
        _stopScan();
      }
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
      _bleLogs.add('[${_time()}] 扫描完成');
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _bleLogs.add('[${_time()}] 正在连接 ${device.name}...');
    });

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;
      _isConnected = true;

      setState(() {
        _bleLogs.add('[${_time()}] 连接成功: ${device.name}');
      });

      // 发现服务和特征
      final services = await device.discoverServices();
      setState(() {
        _bleLogs.add('[${_time()}] 发现 ${services.length} 个服务');
      });

      // 选择第一个可写入的特征
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _selectedCharacteristic = char;
            setState(() {
              _bleLogs.add('[${_time()}] 已选择特征: ${char.uuid}');
            });
            break;
          }
        }
        if (_selectedCharacteristic != null) break;
      }

      // 监听数据
      _characteristicSubscription = _selectedCharacteristic?.lastValueStream.listen((value) {
        setState(() {
          _bleLogs.add('[${_time()}] 收到: ${_formatBytes(Uint8List.fromList(value))}');
        });
      });
    } catch (e) {
      setState(() {
        _bleLogs.add('[${_time()}] 连接失败: $e');
      });
    }
  }

  Future<void> _disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      setState(() {
        _connectedDevice = null;
        _isConnected = false;
        _selectedCharacteristic = null;
        _bleLogs.add('[${_time()}] 已断开连接');
      });
    }
  }

  Future<void> _sendBleMessage() async {
    if (_selectedCharacteristic == null) return;

    final message = _bleMessageController.text;
    if (message.isEmpty) return;

    try {
      // 支持字符串和Hex格式
      Uint8List data;
      if (message.startsWith('0x') || message.startsWith('0X')) {
        // Hex格式
        final hex = message.substring(2);
        data = Uint8List.fromList(_hexToBytes(hex));
      } else {
        // 字符串格式
        data = Uint8List.fromList(utf8.encode(message));
      }

      await _selectedCharacteristic!.write(data, withoutResponse: false);
      setState(() {
        _bleLogs.add('[${_time()}] 发送: $message');
      });
      _bleMessageController.clear();
    } catch (e) {
      setState(() {
        _bleLogs.add('[${_time()}] 发送失败: $e');
      });
    }
  }

  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  String _formatBytes(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  String _time() {
    return DateTime.now().toIso8601String().substring(11, 19);
  }

  Widget _buildBluetoothTab() {
    return Column(
      children: [
        // 控制按钮
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: const Icon(Icons.search),
                  label: Text(_isScanning ? '扫描中...' : '扫描设备'),
                ),
              ),
              if (_isScanning) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _stopScan,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
              ],
              if (_isConnected) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _disconnect,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  icon: const Icon(Icons.link_off),
                  label: const Text('断开'),
                ),
              ],
            ],
          ),
        ),

        // 设备列表
        if (!_isConnected)
          Container(
            height: 150,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _bleDevices.isEmpty
                ? Center(
                    child: Text(
                      _isScanning ? '正在扫描附近设备...' : '点击"扫描设备"开始搜索',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  )
                : ListView.builder(
                    itemCount: _bleDevices.length,
                    itemBuilder: (context, index) {
                      final device = _bleDevices[index];
                      return ListTile(
                        leading: const Icon(Icons.bluetooth),
                        title: Text(device.device.name.isEmpty ? '未知设备' : device.device.name),
                        subtitle: Text('RSSI: ${device.rssi}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _connectToDevice(device.device),
                      );
                    },
                  ),
          ),

        // 已连接设备信息
        if (_isConnected)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_connected, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _connectedDevice?.name ?? '已连接',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_selectedCharacteristic != null)
                        Text(
                          '特征: ${_selectedCharacteristic!.uuid}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // 发送消息
        if (_isConnected)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bleMessageController,
                    decoration: const InputDecoration(
                      labelText: '发送数据 (字符串或0xHex)',
                      border: OutlineInputBorder(),
                      hintText: 'Hello 或 0x48656C6C6F',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _sendBleMessage,
                  icon: const Icon(Icons.send),
                  label: const Text('发送'),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),
        const Divider(height: 1),

        // 日志区域
        Expanded(
          child: _bleLogs.isEmpty
              ? Center(
                  child: Text(
                    '暂无日志',
                    style: TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _bleLogs.length,
                  itemBuilder: (context, index) {
                    final log = _bleLogs[index];
                    final isSent = log.contains('发送:');
                    final isRecv = log.contains('收到:');
                    final isError = log.contains('错误') || log.contains('失败');
                    Color textColor = Colors.black87;
                    if (isSent) textColor = Colors.blue;
                    if (isRecv) textColor = Colors.green;
                    if (isError) textColor = Colors.red;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSent ? Colors.blue.withValues(alpha: 0.1) :
                               isRecv ? Colors.green.withValues(alpha: 0.1) :
                               isError ? Colors.red.withValues(alpha: 0.1) : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: textColor,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

void registerNetworkDemo() {
  demoRegistry.register(NetworkDemo());
}
