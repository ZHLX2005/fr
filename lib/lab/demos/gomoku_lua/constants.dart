// lib/lab/demos/gomoku_lua/constants.dart
// 五子棋 Lua 版 — 常量 + 持久化

import 'package:shared_preferences/shared_preferences.dart';

// ── 持久化 key ──

const String kGomokuRelayUrl = 'http://47.110.80.47:8988';
const String kGomokuAliasKey = 'gomoku_lua.alias';

class GomokuAliasPrefs {
  static Future<String> load() => SharedPreferences.getInstance().then(
    (p) => p.getString(kGomokuAliasKey) ?? '',
  );
  static Future<void> save(String alias) => SharedPreferences.getInstance()
      .then((p) => p.setString(kGomokuAliasKey, alias));
}

// ── 棋盘常量 ──

/// 标准 15x15 棋盘（横竖各 15 条线，225 个交点）
const int kGomokuSize = 15;

/// 连子获胜数（五子连珠）
const int kGomokuWinLength = 5;

// ── 对局布局常量（OnlineGamePage _buildPlaying 用）──
//
// 棋盘放在 Expanded+Center 里垂直居中，任何同级兄弟的高度变化都会让
// Expanded 重新分配高度 → 棋盘居中位置上下抖动。把这两条固定下来：
//   1) 顶部回合条：文案字数不同（"轮到你（黑方）落子" / "等待 白方 落子…"）也保持等高；
//   2) 待确认按钮条：无论是否处于待确认状态都占位，避免出现/消失撑动棋盘。

/// 顶部回合提示条固定高度。
const double kGomokuTurnBarHeight = 44.0;

/// 待确认按钮条预留高度（不待确认时也保留，棋盘区域高度恒定）。
const double kGomokuConfirmBarHeight = 56.0;
