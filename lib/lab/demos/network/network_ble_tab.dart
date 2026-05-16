import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'const_network.dart';
import 'network_widgets.dart';

/// 蓝牙 BLE 测试 Tab
class NetworkBleTab extends StatefulWidget {
  const NetworkBleTab({super.key});

  @override
  State<NetworkBleTab> createState() => _NetworkBleTabState();
}

class _NetworkBleTabState extends State<NetworkBleTab>
    with AutomaticKeepAliveClientMixin {
  List<ScanResult> _devices = [];
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _selectedCharacteristic;
  bool _isScanning = false;
  bool _isConnected = false;
  final List<String> _logs = [];
  final _messageController = TextEditingController();

  bool _filterNamedOnly = false;
  int _minRssi = NetworkConst.rssiMinDefault;
  String _searchKeyword = '';

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _characteristicSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _characteristicSubscription?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _devices.clear();
      _isScanning = true;
      _logs.add('[${NetworkWidgets.shortTime()}] 开始扫描...');
    });

    final permissions = [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ];

    final statuses = await permissions.request();
    final denied =
        statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied) {
      setState(() {
        _logs.add('[${NetworkWidgets.shortTime()}] 错误: 需要蓝牙和位置权限');
        _logs.add('[${NetworkWidgets.shortTime()}] 请在设置中开启权限');
        _isScanning = false;
      });
      return;
    }

    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      setState(() {
        _logs.add('[${NetworkWidgets.shortTime()}] 错误: 蓝牙未开启');
        _isScanning = false;
      });
      return;
    }

    await FlutterBluePlus.startScan(timeout: NetworkConst.bleScanTimeout);

    final Map<String, ScanResult> deviceMap = {};
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final key = r.device.remoteId.str;
        if (!deviceMap.containsKey(key) || r.rssi > deviceMap[key]!.rssi) {
          deviceMap[key] = r;
        }
      }
      setState(() {
        _devices = deviceMap.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
        if (_devices.isNotEmpty) {
          _logs.add(
            '[${NetworkWidgets.shortTime()}] 发现 ${_devices.length} 个设备',
          );
        }
      });
    });

    Future.delayed(NetworkConst.bleScanTimeout, () {
      if (_isScanning) _stopScan();
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
      _logs.add('[${NetworkWidgets.shortTime()}] 扫描完成');
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _logs.add('[${NetworkWidgets.shortTime()}] 正在连接 ${device.name}...');
    });

    try {
      await device.connect(timeout: NetworkConst.bleConnectTimeout);
      _connectedDevice = device;
      _isConnected = true;

      setState(() {
        _logs.add(
            '[${NetworkWidgets.shortTime()}] 连接成功: ${device.name}');
      });

      final services = await device.discoverServices();
      setState(() {
        _logs.add(
            '[${NetworkWidgets.shortTime()}] 发现 ${services.length} 个服务');
      });

      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _selectedCharacteristic = char;
            setState(() {
              _logs.add(
                  '[${NetworkWidgets.shortTime()}] 已选择特征: ${char.uuid}');
            });
            break;
          }
        }
        if (_selectedCharacteristic != null) break;
      }

      _characteristicSubscription = _selectedCharacteristic?.lastValueStream
          .listen((value) {
        setState(() {
          _logs.add(
            '[${NetworkWidgets.shortTime()}] 收到: ${_formatBytes(Uint8List.fromList(value))}',
          );
        });
      });
    } catch (e) {
      setState(() {
        _logs.add('[${NetworkWidgets.shortTime()}] 连接失败: $e');
      });
    }
  }

  Future<void> _disconnect() async {
    if (_connectedDevice == null) return;
    await _connectedDevice!.disconnect();
    setState(() {
      _connectedDevice = null;
      _isConnected = false;
      _selectedCharacteristic = null;
      _logs.add('[${NetworkWidgets.shortTime()}] 已断开连接');
    });
  }

  Future<void> _sendMessage() async {
    if (_selectedCharacteristic == null) return;
    final message = _messageController.text;
    if (message.isEmpty) return;

    try {
      Uint8List data;
      if (message.startsWith('0x') || message.startsWith('0X')) {
        data = Uint8List.fromList(_hexToBytes(message.substring(2)));
      } else {
        data = Uint8List.fromList(utf8.encode(message));
      }
      await _selectedCharacteristic!.write(data, withoutResponse: false);
      setState(() {
        _logs.add('[${NetworkWidgets.shortTime()}] 发送: $message');
      });
      _messageController.clear();
    } catch (e) {
      setState(() {
        _logs.add('[${NetworkWidgets.shortTime()}] 发送失败: $e');
      });
    }
  }

  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i + 2 <= hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  String _formatBytes(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  List<ScanResult> get _filteredDevices {
    return _devices.where((device) {
      final name = device.device.name;
      final isNamed = name.isNotEmpty;
      if (_filterNamedOnly && !isNamed) return false;
      if (device.rssi < _minRssi) return false;
      if (_searchKeyword.isNotEmpty) {
        if (isNamed && !name.toLowerCase().contains(_searchKeyword)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
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
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NetworkConst.colorWarn,
                  ),
                  icon: const Icon(Icons.stop),
                  label: const Text('停止'),
                ),
              ],
              if (_isConnected) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _disconnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NetworkConst.colorError,
                  ),
                  icon: const Icon(Icons.link_off),
                  label: const Text('断开'),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: '搜索设备名称...',
                  prefixIcon: Icon(Icons.filter_list),
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (value) =>
                    setState(() => _searchKeyword = value.toLowerCase()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilterChip(
                    label: const Text('仅显示已命名'),
                    selected: _filterNamedOnly,
                    onSelected: (selected) {
                      setState(() => _filterNamedOnly = selected);
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        const Text('信号>', style: TextStyle(fontSize: 12)),
                        SizedBox(
                          width: 100,
                          child: Slider(
                            value: _minRssi.toDouble(),
                            min: -100,
                            max: -30,
                            divisions: 14,
                            label: '$_minRssi',
                            onChanged: (value) =>
                                setState(() => _minRssi = value.toInt()),
                          ),
                        ),
                        Text('${_minRssi}dBm',
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (!_isConnected)
          SizedBox(
            height: 150,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _devices.isEmpty
                  ? Center(
                      child: Text(
                        _isScanning ? '正在扫描附近设备...' : '点击"扫描设备"开始搜索',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredDevices.length,
                      itemBuilder: (context, index) {
                        final device = _filteredDevices[index];
                        final name = device.device.name;
                        final isNamed = name.isNotEmpty;
                        return ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: isNamed ? Colors.blue : Colors.grey,
                          ),
                          title: Text(isNamed ? name : '未知设备'),
                          subtitle: Row(
                            children: [
                              Text('RSSI: ${device.rssi}'),
                              const SizedBox(width: 8),
                              NetworkWidgets.signalIcon(device.rssi),
                            ],
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _connectToDevice(device.device),
                        );
                      },
                    ),
            ),
          ),
        if (_isConnected)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: NetworkConst.colorSuccess.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: NetworkConst.colorSuccess),
            ),
            child: Row(
              children: [
                const Icon(Icons.bluetooth_connected,
                    color: NetworkConst.colorSuccess),
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
        if (_isConnected)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
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
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  label: const Text('发送'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(
          child: _logs.isEmpty
              ? Center(
                  child: Text(
                    '暂无日志',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[index];
                    final isSent = log.contains('发送:');
                    final isRecv = log.contains('收到:');
                    final isError =
                        log.contains('错误') || log.contains('失败');
                    Color textColor = Colors.black87;
                    Color? bg;
                    if (isSent) {
                      textColor = Colors.blue;
                      bg = Colors.blue.withValues(alpha: 0.1);
                    } else if (isRecv) {
                      textColor = NetworkConst.colorSuccess;
                      bg =
                          NetworkConst.colorSuccess.withValues(alpha: 0.1);
                    } else if (isError) {
                      textColor = NetworkConst.colorError;
                      bg = NetworkConst.colorError.withValues(alpha: 0.1);
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: bg,
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
