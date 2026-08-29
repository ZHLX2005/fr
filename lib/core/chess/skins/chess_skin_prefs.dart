// lib/core/chess/skins/chess_skin_prefs.dart
//
// 换肤偏好 —— SharedPreferences 持久化选中的皮肤 id。
//
// 设计（遵循 lib/core/theme/state/theme_provider.dart 的持久化模式）：
//   · 静态 key const（与主题 _kThemeKey 同级）
//   · read()/write() 各自 getInstance，轻量无状态
//   · 无记录时回退 kChessSkinsCatalog.first.id（'1'，与 ChessRoomPage.skinId 默认值一致）
//
// 说明：不引入 Riverpod，游戏入口 demo 是 StatefulWidget，读一次 + setState 即可；
// 若未来要全局广播换肤，再升级为 Notifier（与 ThemeNotifier 对齐）。

import 'package:shared_preferences/shared_preferences.dart';

import 'chess_skin_meta.dart';

/// 换肤偏好 —— SharedPreferences 持久化选中的皮肤 id。
class ChessSkinPrefs {
  ChessSkinPrefs._();

  /// SharedPreferences key（换肤 id）。
  static const String _key = 'chess_skin_id';

  /// 读取当前皮肤 id（无记录时回退 catalog 第一套，即 '1'）。
  static Future<String> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? kChessSkinsCatalog.first.id;
  }

  /// 写入皮肤 id（持久化）。
  static Future<void> write(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }
}
