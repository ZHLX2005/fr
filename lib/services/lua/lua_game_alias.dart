// lib/services/lua/lua_game_alias.dart
//
// Lua 房间对战游戏的**共享昵称** reference。
//
// 设计目标：gomoku / surround / tetris / reversi（以及未来任何 Lua 房间游戏）
// 共用同一个昵称——用户在任何一处输入，所有游戏都立即看到最新值。
//
// 实现要点：
//   - 统一 SharedPreferences key：`lua_game.alias`（取代分散的 gomoku_lua.alias 等）
//   - 全局 ValueNotifier 作 reference：widget 用 ValueListenableBuilder / addListener
//     监听，一处 save → 所有监听者实时响应
//   - load() 兼容迁移：新 key 为空时，尝试从历史 4 个 key 读一个非空值
//
// 用法：
//   ```dart
//   // initState
//   final v = await LuaGameAlias.load();
//   if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
//     _aliasCtrl.text = v;
//   }
//   LuaGameAlias.notifier.addListener(_onAliasChanged);
//
//   // TextField
//   TextField(
//     controller: _aliasCtrl,
//     onChanged: (v) => LuaGameAlias.save(v),  // 实时写 + 实时同步
//   )
//   ```

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 统一的 Lua 房间游戏昵称 key。
const String kLuaGameAliasKey = 'lua_game.alias';

/// 历史 key（迁移用）：load 时若新 key 为空，按顺序尝试这些旧 key。
const List<String> _legacyAliasKeys = [
  'gomoku_lua.alias',
  'surround_game_lua.alias',
  'tetris_lua.alias',
  'reversi_lua.alias',
];

/// Lua 房间游戏共享昵称（全局单例 reference）。
///
/// 所有 Lua 房间游戏（gomoku / surround / tetris / reversi…）共用这一个昵称。
/// 一处 save → 所有监听 [notifier] 的页面实时响应。
class LuaGameAlias {
  LuaGameAlias._();

  /// 全局 reference：当前昵称。widget 通过 [notifier] 监听变化。
  static final ValueNotifier<String> notifier = ValueNotifier<String>('');

  /// 是否已从磁盘加载过（避免空值覆盖回填前先返回空）。
  static bool _loaded = false;

  /// 当前昵称（同步读，不触发监听）。
  static String get value => notifier.value;

  /// 从 SharedPreferences 加载；首次加载会兼容迁移老 key。
  /// 多次调用安全（已加载则直接返回当前 value）。
  static Future<String> load() async {
    if (_loaded) return notifier.value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var v = prefs.getString(kLuaGameAliasKey) ?? '';
      // 迁移：新 key 为空时，从历史 key 读一个非空的
      if (v.isEmpty) {
        for (final legacy in _legacyAliasKeys) {
          final old = prefs.getString(legacy);
          if (old != null && old.isNotEmpty) {
            v = old;
            // 顺手写入新 key，下次直接命中
            await prefs.setString(kLuaGameAliasKey, v);
            break;
          }
        }
      }
      notifier.value = v;
    } catch (_) {
      // 加载失败保持空值，不阻塞 UI
    }
    return notifier.value;
  }

  /// 保存昵称：同步更新 [notifier]（实时通知监听者）+ 异步持久化。
  /// 空字符串不持久化（避免清空时写空串覆盖）。
  static Future<void> save(String alias) async {
    final v = alias.trim();
    // 先更新内存 reference（实时响应），即使相等也设置（ValueNotifier 内部会判等跳过通知）
    notifier.value = v;
    if (v.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLuaGameAliasKey, v);
    } catch (_) {
      // 持久化失败不影响内存 reference
    }
  }
}
