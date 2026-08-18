import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'const_network.dart';
import 'network_widgets.dart';

/// BLE 日志列表 —— 自动根据"发送/收到/错误"染色
class BleLogList extends StatelessWidget {
  final List<String> logs;
  const BleLogList({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Center(
        child: Text(
          '暂无日志',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final isSent = log.contains('发送:');
        final isRecv = log.contains('收到:');
        final isError = log.contains('错误') || log.contains('失败');
        Color textColor = Colors.black87;
        Color? bg;
        if (isSent) {
          textColor = Colors.blue;
          bg = Colors.blue.withValues(alpha: 0.1);
        } else if (isRecv) {
          textColor = NetworkConst.colorSuccess;
          bg = NetworkConst.colorSuccess.withValues(alpha: 0.1);
        } else if (isError) {
          textColor = NetworkConst.colorError;
          bg = NetworkConst.colorError.withValues(alpha: 0.1);
        }
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }
}

/// BLE 设备列表 —— 单条设备：名称、RSSI、信号强度图标
class BleDeviceList extends StatelessWidget {
  final List<ScanResult> devices;
  final bool isScanning;
  final ValueChanged<BluetoothDevice> onTap;

  const BleDeviceList({
    super.key,
    required this.devices,
    required this.isScanning,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return Center(
        child: Text(
          isScanning ? '正在扫描附近设备...' : '点击"扫描设备"开始搜索',
          style: TextStyle(
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
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
          onTap: () => onTap(device.device),
        );
      },
    );
  }
}

/// 已连接设备的信息条
class BleConnectedBanner extends StatelessWidget {
  final BluetoothDevice device;
  final BluetoothCharacteristic? characteristic;

  const BleConnectedBanner({
    super.key,
    required this.device,
    required this.characteristic,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: NetworkConst.colorSuccess.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NetworkConst.colorSuccess),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.bluetooth_connected,
            color: NetworkConst.colorSuccess,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name.isEmpty ? '已连接' : device.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (characteristic != null)
                  Text(
                    '特征: ${characteristic!.uuid}',
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
    );
  }
}
