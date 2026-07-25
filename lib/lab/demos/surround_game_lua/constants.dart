// lib/lab/demos/surround_game_lua/constants.dart
// 围追堵截 Lua 版 — 常量 + 持久化

import 'package:shared_preferences/shared_preferences.dart';

// ── 持久化 key ──

const String kSgRelayUrl = 'http://47.110.80.47:8988';
const String kSgAliasKey = 'surround_game_lua.alias';

class SgAliasPrefs {
  static Future<String> load() =>
      SharedPreferences.getInstance().then((p) => p.getString(kSgAliasKey) ?? '');
  static Future<void> save(String alias) =>
      SharedPreferences.getInstance().then((p) => p.setString(kSgAliasKey, alias));
}

// ── 阶段枚举 ──

enum SgLobbyPhase { entering, waitingAck, waitingDeal, playing, ended }
