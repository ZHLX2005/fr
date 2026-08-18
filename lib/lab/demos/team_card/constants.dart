// lib/lab/demos/team_card/constants.dart
// 团建卡牌 — 常量 + 数据模型 + 持久化

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── 持久化 key ──

const String kTeamCardRelayUrl = 'http://47.110.80.47:8988';
const String kTeamCardAliasKey = 'team_card_lua.alias';
const String kTeamCardSetupKey = 'team_card_lua.setup_v2';       // 上次配置（int 数量 + 当前池）
const String kTeamCardPresetsKey = 'team_card_lua.presets_v2';    // 命名预设库（Map<int, List<NamedPreset>>）

// ── 别名持久化 ──

class AliasPrefs {
  static Future<String> load() =>
      SharedPreferences.getInstance().then((p) => p.getString(kTeamCardAliasKey) ?? '');
  static Future<void> save(String alias) =>
      SharedPreferences.getInstance().then((p) => p.setString(kTeamCardAliasKey, alias));
}

// ── 角色定义 ──

class RoleDef {
  RoleDef({required this.label, this.count = 1})
      : nameCtrl = TextEditingController(text: label),
        countCtrl = TextEditingController(text: count.toString());

  String label;
  int count;
  final TextEditingController nameCtrl;
  final TextEditingController countCtrl;

  void sync() {
    label = nameCtrl.text.trim().isEmpty ? '?' : nameCtrl.text.trim();
    count = (int.tryParse(countCtrl.text) ?? 1).clamp(1, 99);
  }

  void dispose() {
    nameCtrl.dispose();
    countCtrl.dispose();
  }

  Map<String, dynamic> toJson() => {'label': label, 'count': count};

  factory RoleDef.fromJson(Map<String, dynamic> j) =>
      RoleDef(label: j['label'] as String? ?? '', count: (j['count'] as num?)?.toInt() ?? 1);
}

// ── 角色颜色 ──

Color roleColor(ThemeData theme, String role) {
  if (role == '卧底' || role == '狼人') return theme.colorScheme.error;
  if (role == '预言家') return Colors.blue;
  if (role == '女巫') return theme.colorScheme.tertiary;
  if (role == '猎人' || role == '守卫') return Colors.teal;
  return theme.colorScheme.primary;
}

// ── 内置预设 ──

typedef RoleRecord = ({String label, int count});

class RolePreset {
  final String name;
  final List<RoleRecord> roles;
  const RolePreset({required this.name, required this.roles});
  int get total => roles.fold(0, (s, r) => s + r.count);
  List<RoleDef> toRoleDefs() => roles.map((r) => RoleDef(label: r.label, count: r.count)).toList();
}

const List<RolePreset> kBuiltinPresets = [
  RolePreset(name: '谁是卧底（4人）', roles: [(label: '卧底', count: 1), (label: '平民', count: 3)]),
  RolePreset(name: '谁是卧底（6人）', roles: [(label: '卧底', count: 1), (label: '平民', count: 5)]),
  RolePreset(name: '谁是卧底（8人）', roles: [(label: '卧底', count: 2), (label: '平民', count: 6)]),
  RolePreset(
      name: '狼人杀（6人）',
      roles: [
        (label: '狼人', count: 2),
        (label: '预言家', count: 1),
        (label: '女巫', count: 1),
        (label: '村民', count: 2),
      ]),
  RolePreset(
      name: '狼人杀（8人）',
      roles: [
        (label: '狼人', count: 2),
        (label: '预言家', count: 1),
        (label: '女巫', count: 1),
        (label: '猎人', count: 1),
        (label: '村民', count: 3),
      ]),
  RolePreset(
      name: '狼人杀（12人）',
      roles: [
        (label: '狼人', count: 4),
        (label: '预言家', count: 1),
        (label: '女巫', count: 1),
        (label: '猎人', count: 1),
        (label: '守卫', count: 1),
        (label: '村民', count: 4),
      ]),
];

// ── 命名预设（用户自定义，按 playerSlots 分组） ──

class NamedPreset {
  final String name;
  final List<Map<String, dynamic>> roles; // [{label, count}, ...]
  const NamedPreset({required this.name, required this.roles});

  int get total => roles.fold(0, (s, r) => s + ((r['count'] as num?)?.toInt() ?? 0));

  List<RoleDef> toRoleDefs() => roles
      .map((r) => RoleDef(
            label: r['label'] as String? ?? '',
            count: (r['count'] as num?)?.toInt() ?? 1,
          ))
      .toList();

  Map<String, dynamic> toJson() => {'name': name, 'roles': roles};

  factory NamedPreset.fromJson(Map<String, dynamic> j) => NamedPreset(
        name: j['name'] as String? ?? '',
        roles: (j['roles'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

  factory NamedPreset.fromRoleDefs(String name, List<RoleDef> defs) => NamedPreset(
        name: name,
        roles: defs.map((r) => {'label': r.label, 'count': r.count}).toList(),
      );
}

/// 用户命名预设库：`{ playerSlots(String): [NamedPreset, ...] }`
///
/// 按玩家区人数分组，每组可存多个命名预设。
class PresetLibrary {
  static Future<Map<int, List<NamedPreset>>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(kTeamCardPresetsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(
            int.tryParse(k) ?? 0,
            (v as List)
                .map((e) => NamedPreset.fromJson(e as Map<String, dynamic>))
                .toList(),
          ));
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<int, List<NamedPreset>> lib) async {
    final data = jsonEncode(lib.map(
      (k, v) => MapEntry(k.toString(), v.map((p) => p.toJson()).toList()),
    ));
    final p = await SharedPreferences.getInstance();
    await p.setString(kTeamCardPresetsKey, data);
  }

  /// 添加新命名预设到指定 playerSlots 分组
  static Future<Map<int, List<NamedPreset>>> add({
    required int playerSlots,
    required NamedPreset preset,
  }) async {
    final lib = await load();
    final list = List<NamedPreset>.from(lib[playerSlots] ?? []);
    // 同名替换
    list.removeWhere((p) => p.name == preset.name);
    list.add(preset);
    lib[playerSlots] = list;
    await save(lib);
    return lib;
  }

  /// 从指定 playerSlots 分组删除命名预设
  static Future<Map<int, List<NamedPreset>>> remove({
    required int playerSlots,
    required String name,
  }) async {
    final lib = await load();
    final list = List<NamedPreset>.from(lib[playerSlots] ?? []);
    list.removeWhere((p) => p.name == name);
    if (list.isEmpty) {
      lib.remove(playerSlots);
    } else {
      lib[playerSlots] = list;
    }
    await save(lib);
    return lib;
  }
}

// ── 上次配置持久化（playerSlots + spectatorSlots + rolePool） ──

class SetupPrefs {
  static Future<SetupState?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(kTeamCardSetupKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return SetupState(
        playerSlots: (j['player_slots'] as num?)?.toInt() ?? 4,
        spectatorSlots: (j['spectator_slots'] as num?)?.toInt() ?? 0,
        roles: (j['roles'] as List? ?? [])
            .map((e) => RoleDef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(SetupState s) async {
    final data = jsonEncode({
      'player_slots': s.playerSlots,
      'spectator_slots': s.spectatorSlots,
      'roles': s.roles.map((r) => {'label': r.label, 'count': r.count}).toList(),
    });
    final p = await SharedPreferences.getInstance();
    await p.setString(kTeamCardSetupKey, data);
  }
}

class SetupState {
  final int playerSlots;
  final int spectatorSlots;
  final List<RoleDef> roles;
  const SetupState({
    required this.playerSlots,
    required this.spectatorSlots,
    required this.roles,
  });
}

// ── 头像颜色表（复制自 participants_grid.dart 的 kParticipantColors） ──

const List<Color> kTeamCardAvatarColors = [
  Color(0xFF4F8CF7),
  Color(0xFF34C759),
  Color(0xFFFF9500),
  Color(0xFFAF52DE),
  Color(0xFF5AC8FA),
  Color(0xFFFF2D55),
  Color(0xFF5856D6),
  Color(0xFF00C7BE),
  Color(0xFFFFD60A),
  Color(0xFFFF6B6B),
  Color(0xFFA2845E),
  Color(0xFFBF5AF2),
];
