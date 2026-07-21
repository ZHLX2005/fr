// lib/lab/demos/team_card/team_card_types.dart
// 团建卡牌模块共享模型 + 身份预设

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 身份定义（可编辑）
class RoleDef {
  RoleDef({required this.label, this.count = 1, this.key})
      : nameCtrl = TextEditingController(text: label),
        countCtrl = TextEditingController(text: count.toString());

  String label;
  int count;
  final String? key;
  final TextEditingController nameCtrl;
  final TextEditingController countCtrl;

  int get total => count;

  void sync() {
    label = nameCtrl.text;
    count = max(1, int.tryParse(countCtrl.text) ?? 1);
  }

  void dispose() {
    nameCtrl.dispose();
    countCtrl.dispose();
  }

  Map<String, dynamic> toJson() => {'label': label, 'count': count};
  factory RoleDef.fromJson(Map<String, dynamic> j, {String? key}) =>
      RoleDef(label: j['label'] as String? ?? '', count: (j['count'] as num?)?.toInt() ?? 1, key: key);
}

/// 发牌结果中的一张卡牌
class CardInfo {
  final String deviceId;
  final String alias;
  final String role;
  CardInfo({required this.deviceId, required this.alias, required this.role});
}

/// 身份颜色映射
Color roleColor(ThemeData theme, String role) {
  if (role == '卧底' || role == '狼人') return theme.colorScheme.error;
  if (role == '预言家') return Colors.blue;
  if (role == '女巫') return Colors.purple;
  return theme.colorScheme.primary;
}

/// 内置预设模板
class RolePreset {
  final String name;
  final List<({String label, int count})> roles;

  const RolePreset({required this.name, required this.roles});

  /// 预设对应的房间人数（角色总和）
  int get total => roles.fold(0, (s, r) => s + r.count);

  /// 生成 RoleDef 列表
  List<RoleDef> toRoleDefs() {
    var kc = 0;
    return roles.map((r) => RoleDef(label: r.label, count: r.count, key: 'k${kc++}')).toList();
  }
}

/// 内置预选方案
({String label, int count}) _r(String l, int c) => (label: l, count: c);
final kBuiltinPresets = <RolePreset>[
  RolePreset(name: '谁是卧底(4人)', roles: [_r('卧底', 1), _r('平民', 3)]),
  RolePreset(name: '谁是卧底(6人)', roles: [_r('卧底', 1), _r('平民', 5)]),
  RolePreset(name: '谁是卧底(8人)', roles: [_r('卧底', 2), _r('平民', 6)]),
  RolePreset(name: '狼人杀(6人)', roles: [_r('狼人', 2), _r('预言家', 1), _r('女巫', 1), _r('村民', 2)]),
  RolePreset(name: '狼人杀(8人)', roles: [_r('狼人', 2), _r('预言家', 1), _r('女巫', 1), _r('猎人', 1), _r('村民', 3)]),
  RolePreset(name: '狼人杀(12人)', roles: [_r('狼人', 4), _r('预言家', 1), _r('女巫', 1), _r('猎人', 1), _r('守卫', 1), _r('村民', 4)]),
];

/// 自定义预设持久化
class CustomPresetPrefs {
  static const _kKey = 'team_card.custom_presets';

  static Future<void> save(List<RoleDef> roles) async {
    final data = jsonEncode(roles.map((r) => r.toJson()).toList());
    await (await SharedPreferences.getInstance()).setString(_kKey, data);
  }

  static Future<List<RoleDef>?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List;
      var kc = 0;
      return list.map((e) => RoleDef.fromJson(e as Map<String, dynamic>, key: 'ck${kc++}')).toList();
    } catch (_) {
      return null;
    }
  }
}
