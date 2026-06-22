// lib/core/jungle_chess/lan/persistence/player_profile_service.dart
//
// 本机 alias 持久化
//
// 策略：
// - loadAlias：未设置返回 null
// - saveAlias：空字符串视为删除（写回 null 状态）

import 'package:shared_preferences/shared_preferences.dart';

class PlayerProfileService {
  static const String _keyAlias = 'jungle_lan_player_alias';

  /// 加载本机 alias（null=未设置）
  static Future<String?> loadAlias() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAlias);
  }

  /// 持久化 alias（空字符串视为删除）
  static Future<void> saveAlias(String alias) async {
    final prefs = await SharedPreferences.getInstance();
    if (alias.isEmpty) {
      await prefs.remove(_keyAlias);
    } else {
      await prefs.setString(_keyAlias, alias);
    }
  }
}
