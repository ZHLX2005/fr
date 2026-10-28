// team_card 上次配置持久化（自 constants.dart 拆出，2026-10-28 配置/代码分离）
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'constants.dart';

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
