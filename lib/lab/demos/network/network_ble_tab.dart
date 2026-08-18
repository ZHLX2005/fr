import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'const_network.dart';
import 'network_ble_service.dart';
import 'network_ble_views.dart';
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

  void _log(String msg) {
    if (!mounted) return;
    setState(() => _logs.add('[${NetworkWidgets.shortTime()}] $msg'));
  }

  Future<void> _startScan() async {
    setState(() {
      _devices.clear();
      _isScanning = true;
    });
    _log('开始扫描...');

    if (!await NetworkBleService.ensurePermissions()) {
      _log('错误: 需要蓝牙和位置权限');
      _log('请在设置中开启权限');
      if (mounted) setState(() => _isScanning = false);
      return;
    }

    if (!await NetworkBleService.isBluetoothOn()) {
      _log('错误: 蓝牙未开启');
      if (mounted) setState(() => _isScanning = false);
      return;
    }

    await FlutterBluePlus.startScan(timeout: NetworkConst.bleScanTimeout);

    final deviceMap = <String, ScanResult>{};
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final key = r.device.remoteId.str;
        if (!deviceMap.containsKey(key) || r.rssi > deviceMap[key]!.rssi) {
          deviceMap[key] = r;
        }
      }
      if (!mounted) return;
      setState(() {
        _devices = deviceMap.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    Future.delayed(NetworkConst.bleScanTimeout, () {
      if (_isScanning) _stopScan();
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    if (mounted) setState(() => _isScanning = false);
    _log('扫描完成');
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    _log('正在连接 ${device.name}...');
    try {
      await device.connect(timeout: NetworkConst.bleConnectTimeout);
      _connectedDevice = device;
      if (mounted) setState(() => _isConnected = true);
      _log('连接成功: ${device.name}');

      final char = await NetworkBleService.findWritableCharacteristic(device);
      if (char != null) {
        _selectedCharacteristic = char;
        _log('已选择特征: ${char.uuid}');
        _characteristicSubscription = char.lastValueStream.listen((value) {
          _log('收到: ${NetworkBleService.formatBytes(Uint8List.fromList(value))}');
        });
      } else {
        _log('未找到可写特征');
      }
    } catch (e) {
      _log('连接失败: $e');
    }
  }

  Future<void> _disconnect() async {
    if (_connectedDevice == null) return;
    await _connectedDevice!.disconnect();
    if (mounted) {
      setState(() {
        _connectedDevice = null;
        _isConnected = false;
        _selectedCharacteristic = null;
      });
    }
    _log('已断开连接');
  }

  Future<void> _sendMessage() async {
    if (_selectedCharacteristic == null) return;
    final message = _messageController.text;
    if (message.isEmpty) return;

    try {
      final data = NetworkBleService.encodeMessage(message);
      await _selectedCharacteristic!.write(data, withoutResponse: false);
      _log('发送: $message');
      _messageController.clear();
    } catch (e) {
      _log('发送失败: $e');
    }
  }

  List<ScanResult> get _filteredDevices {
    return _devices.where((d) {
      final name = d.device.name;
      final isNamed = name.isNotEmpty;
      if (_filterNamedOnly && !isNamed) return false;
      if (d.rssi < _minRssi) return false;
      if (_searchKeyword.isNotEmpty &&
          isNamed &&
          !name.toLowerCase().contains(_searchKeyword)) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildControlRow(),
        _buildFilterRow(),
        const SizedBox(height: 8),
        if (!_isConnected)
          SizedBox(
            height: 150,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: BleDeviceList(
                devices: _filteredDevices,
                isScanning: _isScanning,
                onTap: _connectToDevice,
              ),
            ),
          ),
        if (_isConnected) ...[
          BleConnectedBanner(
            device: _connectedDevice!,
            characteristic: _selectedCharacteristic,
          ),
          const SizedBox(height: 8),
          _buildSendRow(),
        ],
        const SizedBox(height: 8),
        const Divider(height: 1),
        Expanded(child: BleLogList(logs: _logs)),
      ],
    );
  }

  Widget _buildControlRow() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _isScanning ? null : _startScan,
              icon: const Icon(Icons.search),
              label: Text(_isScanning ? '扫描中...' : '扫描设备'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: BorderSide(
                    color: Colors.blue.withValues(alpha: 0.5)),
              ),
            ),
          ),
          if (_isScanning) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _stopScan,
              icon: const Icon(Icons.stop),
              label: const Text('停止'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NetworkConst.colorWarn,
                side: BorderSide(
                    color: NetworkConst.colorWarn.withValues(alpha: 0.5)),
              ),
            ),
          ],
          if (_isConnected) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _disconnect,
              icon: const Icon(Icons.link_off),
              label: const Text('断开'),
              style: OutlinedButton.styleFrom(
                foregroundColor: NetworkConst.colorError,
                side: BorderSide(
                    color: NetworkConst.colorError.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
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
                onSelected: (selected) =>
                    setState(() => _filterNamedOnly = selected),
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
    );
  }

  Widget _buildSendRow() {
    return Padding(
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
          OutlinedButton.icon(
            onPressed: _sendMessage,
            icon: const Icon(Icons.send),
            label: const Text('发送'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue,
              side: BorderSide(
                  color: Colors.blue.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}
