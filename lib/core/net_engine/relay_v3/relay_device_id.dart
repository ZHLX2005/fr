import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 设备级稳定的 relay device_id。
///
/// 首次生成 UUID 存 SharedPreferences，之后跨次进入房间复用同一 id。
/// 让"重新进入房间 / 断线超 grace 后重进"被服务端识别为同一玩家，
/// 从而恢复房主/角色身份（host_id、top_player_id 等绑 device_id 的字段）。
///
/// 替换各处 `'xxx-${DateTime.now().microsecondsSinceEpoch}'` 现生成——
/// 那种每次新 id 会导致身份错乱（原房主重进变访客，房间无主锁死）。
class RelayDeviceId {
  static const _key = 'relay_device_id';
  static String? _cached;

  /// 返回稳定的 device_id（首次生成并持久化，之后复用）。
  static Future<String> get() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_key);
    if (id == null || id.isEmpty) {
      id = 'dev-${const Uuid().v4()}';
      await prefs.setString(_key, id);
    }
    _cached = id;
    return id;
  }
}
