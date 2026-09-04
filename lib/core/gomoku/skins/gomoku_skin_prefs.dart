// lib/core/gomoku/skins/gomoku_skin_prefs.dart

import 'package:shared_preferences/shared_preferences.dart';

import 'gomoku_skin_meta.dart';

class GomokuSkinPrefs {
  GomokuSkinPrefs._();
  static const String _key = 'gomoku_skin_id';
  static Future<String> read() async {
    final prefs = await SharedPreferences.getInstance();
    // 空 catalog 时回退 default（与 GomokuSkinBundle.byId('default') 对齐）
    return prefs.getString(_key) ?? 'default';
  }

  static Future<void> write(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }

  // 兼容旧 catalog 非空时的首项回退（未来 catalog 填入后可用）
  static String get fallbackId =>
      kGomokuSkinsCatalog.isNotEmpty ? kGomokuSkinsCatalog.first.id : 'default';
}
