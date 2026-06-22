// lib/core/jungle_chess/lan/persistence/device_id_service.dart
//
// 本机 deviceId 持久化
//
// 为什么需要：LanFramework 每次 start 都会生成新 UUID，导致设备
// 退出 demo 再回来后 deviceId 变化——对端会同时看到"老 B 离线"和"新 B 上线"
// 两条记录。重连时容易误判为"两个会话指向同一设备"。
//
// 策略：
// - 首次启动生成 UUID v4，写入 SharedPreferences
// - 之后启动直接读取，保证本机 identity 跨进程稳定

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  static const String _key = 'jungle_lan_device_id';
  static const _uuid = Uuid();

  /// 加载本机 deviceId，没有就生成并落盘
  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = _uuid.v4();
    await prefs.setString(_key, fresh);
    return fresh;
  }
}
