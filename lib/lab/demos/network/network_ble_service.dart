import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// 蓝牙 BLE 服务（静态方法，无状态）
class NetworkBleService {
  NetworkBleService._();

  /// 请求蓝牙 + 位置权限。返回 true 表示全部 granted。
  static Future<bool> ensurePermissions() async {
    final statuses = await [
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return !statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
  }

  /// 蓝牙是否打开
  static Future<bool> isBluetoothOn() async {
    return await FlutterBluePlus.adapterState.first ==
        BluetoothAdapterState.on;
  }

  /// 查找第一个支持写入的特征（write 或 writeWithoutResponse）
  static Future<BluetoothCharacteristic?> findWritableCharacteristic(
    BluetoothDevice device,
  ) async {
    final services = await device.discoverServices();
    for (final service in services) {
      for (final char in service.characteristics) {
        if (char.properties.write || char.properties.writeWithoutResponse) {
          return char;
        }
      }
    }
    return null;
  }

  /// 16 进制字符串 → 字节数组
  static List<int> hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i + 2 <= hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// 字节数组 → 用空格分隔的 hex 字符串
  static String formatBytes(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  /// 编码用户输入：0x 前缀视为 hex；否则按 UTF-8 编码
  static Uint8List encodeMessage(String message) {
    if (message.startsWith('0x') || message.startsWith('0X')) {
      return Uint8List.fromList(hexToBytes(message.substring(2)));
    }
    return Uint8List.fromList(utf8.encode(message));
  }
}
