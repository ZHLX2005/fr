// lib/lab/demos/team_card/constants.dart
// 团建卡牌 — 常量 + 数据模型

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── 持久化 key ──

const String kTeamCardRelayUrl = 'http://47.110.80.47:8988';
const String kTeamCardAliasKey = 'team_card_lua.alias';
const String kTeamCardCustomKey = 'team_card_lua.custom_preset';

// ── 别名持久化 ──

class AliasPrefs {
  static Future<String> load() =>
      SharedPreferences.getInstance().then((p) => p.getString(kTeamCardAliasKey) ?? '');
  static Future<void> save(String alias) =>
      SharedPreferences.getInstance().then((p) => p.setString(kTeamCardAliasKey, alias));
}

// ── 自定义预设持久化 ──

class CustomPresetPrefs {
  static Future<void> save(List<RoleDef> roles) async {
    final data = jsonEncode(roles.map((r) => r.toJson()).toList());
    final p = await SharedPreferences.getInstance();
    await p.setString(kTeamCardCustomKey, data);
  }

  static Future<List<RoleDef>?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(kTeamCardCustomKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as List)
          .map((e) => RoleDef.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return null;
    }
  }
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
