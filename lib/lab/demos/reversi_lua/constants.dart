// lib/lab/demos/reversi_lua/constants.dart
// 黑白翻转棋 Lua 版 — 常量 + 持久化

import 'package:shared_preferences/shared_preferences.dart';

// ── 持久化 key ──

const String kReversiRelayUrl = 'http://47.110.80.47:8988';
const String kReversiAliasKey = 'reversi_lua.alias';

class ReversiAliasPrefs {
  static Future<String> load() => SharedPreferences.getInstance().then(
        (p) => p.getString(kReversiAliasKey) ?? '',
      );
  static Future<void> save(String alias) =>
      SharedPreferences.getInstance()
          .then((p) => p.setString(kReversiAliasKey, alias));
}

// ── 棋盘常量 ──

/// 标准 8x8 翻转棋棋盘。
const int kReversiSize = 8;