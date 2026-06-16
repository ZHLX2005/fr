import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 本机 deviceId 持久化
///
/// **为什么需要**：LanFramework 每次 start 都会生成新 UUID，导致设备
/// 退出 demo 再回来后 deviceId 变化——对端会同时看到"老 B 离线"和"新 B 上线"
/// 两条记录。重连时容易误判为"两个会话指向同一设备"。
///
/// **策略**：
/// - 首次启动生成 UUID v4，写入 SharedPreferences
/// - 之后启动直接读取，保证本机 identity 跨进程稳定
/// - "重置为默认"按钮会清空 key，让用户拿全新 ID（调试用）
class DeviceIdService {
  static const String _key = 'localnet_device_id';
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

  /// 清空（重置为默认）— 下次 load 时会重新生成
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
