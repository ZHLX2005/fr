// lib/lab/demos/coup_lua/constants.dart
// 政变（Coup）Lua 版 — 常量 + 持久化

import 'package:shared_preferences/shared_preferences.dart';

// ── 持久化 key ──

const String kCoupRelayUrl = 'http://47.110.80.47:8988';
const String kCoupAliasKey = 'coup_lua.alias';

class CoupAliasPrefs {
  static Future<String> load() async {
    // 跨游戏共享 LuaGameAlias；这里只读，不重复持久化。
    final p = await SharedPreferences.getInstance();
    return p.getString(kCoupAliasKey) ?? '';
  }

  static Future<void> save(String alias) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kCoupAliasKey, alias);
  }
}

// ── 角色卡 ──

/// 5 种角色（每种 3 张，共 15 张）。
enum CoupRole {
  duke, // 公爵 — TAX(+3) / 阻断 FOREIGN_AID
  assassin, // 刺客 — ASSASSINATE(-3,目标失 1 卡) / 被 Contessa 阻断
  captain, // 队长 — STEAL / 阻断 STEAL
  ambassador, // 大使 — EXCHANGE / 阻断 STEAL
  contessa, // 伯爵夫人 — 阻断 ASSASSINATE
}

const int kCoupDeckSize = 15; // 3 × 5 角色

// ── 主动作 ──

enum CoupAction {
  income, // +1 金币，无质疑
  foreignAid, // +2 金币，可被 Duke 阻断
  coup, // -7 金币，目标失 1 卡（强制，无阻断）
  exchange, // EXCHANGE：从牌库换 2 张，可被质疑 Ambassador
  assassinate, // -3 金币，目标失 1 卡，可被 Contessa 阻断
  steal, // 从目标偷 1~2 金币，可被 Captain/Ambassador 阻断
  tax, // +3 金币，可被质疑 Duke
}

// ── 响应动作 ──

enum CoupResponse {
  pass, // 不响应
  challenge, // 质疑（动作或阻断）
  block, // 阻断（仅 foreign_aid/steal/assassinate）
}

// ── 阶段（与 Lua c.cur_phase 对应） ──

enum CoupPhase {
  action, // 等待当前玩家选动作
  challenge, // 等待其他玩家质疑/不质疑
  reveal, // 等待被质疑方翻牌/认输（质疑成功后进入）
  block, // 等待阻断（仅可阻断的动作）
  blockChallenge, // 等待动作发起人对阻断反质疑
  loseCard, // 等待失去的卡
  exchange, // 等待选择保留哪 2 张
  ended, // 游戏结束
}

// ── 便捷映射 ──

const Map<CoupAction, String> kCoupActionWire = {
  CoupAction.income: 'INCOME',
  CoupAction.foreignAid: 'FOREIGN_AID',
  CoupAction.coup: 'COUP',
  CoupAction.exchange: 'EXCHANGE',
  CoupAction.assassinate: 'ASSASSINATE',
  CoupAction.steal: 'STEAL',
  CoupAction.tax: 'TAX',
};

CoupAction? actionFromWire(String s) {
  for (final e in kCoupActionWire.entries) {
    if (e.value == s) return e.key;
  }
  return null;
}

CoupRole? roleFromWire(String s) {
  for (final r in CoupRole.values) {
    if (r.name == s) return r;
  }
  return null;
}

String roleLabel(CoupRole r) {
  switch (r) {
    case CoupRole.duke:
      return '公爵';
    case CoupRole.assassin:
      return '刺客';
    case CoupRole.captain:
      return '队长';
    case CoupRole.ambassador:
      return '大使';
    case CoupRole.contessa:
      return '伯爵夫人';
  }
}

String actionLabel(CoupAction a) {
  switch (a) {
    case CoupAction.income:
      return '收入 (+1)';
    case CoupAction.foreignAid:
      return '外援 (+2)';
    case CoupAction.coup:
      return '政变 (-7)';
    case CoupAction.exchange:
      return '换牌';
    case CoupAction.assassinate:
      return '刺杀 (-3)';
    case CoupAction.steal:
      return '偷窃';
    case CoupAction.tax:
      return '征税 (+3)';
  }
}