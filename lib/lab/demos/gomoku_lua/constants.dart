// lib/lab/demos/gomoku_lua/constants.dart
// 五子棋 Lua 版 — 常量 + 持久化

import 'package:shared_preferences/shared_preferences.dart';

// ── 持久化 key ──

const String kGomokuRelayUrl = 'http://47.110.80.47:8988';
const String kGomokuAliasKey = 'gomoku_lua.alias';

class GomokuAliasPrefs {
  static Future<String> load() =>
      SharedPreferences.getInstance().then((p) => p.getString(kGomokuAliasKey) ?? '');
  static Future<void> save(String alias) =>
      SharedPreferences.getInstance().then((p) => p.setString(kGomokuAliasKey, alias));
}

// ── 棋盘常量 ──

/// 标准 15x15 棋盘（横竖各 15 条线，225 个交点）
const int kGomokuSize = 15;

/// 连子获胜数（五子连珠）
const int kGomokuWinLength = 5;
