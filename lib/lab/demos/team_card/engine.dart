// lib/lab/demos/team_card/engine.dart
// 团建卡牌 — Lua 状态机封装 + 语义动作方法
//
// 提供：
//   - kTeamCardScript（从 team_card_script.dart 引用，脚本随本 demo 走）
//   - TeamCardRoom — 围绕 RoomHandle 的语义封装
//
// 调用方只用语义方法如 ack(), sit(), deal(), reset() 等，
// 不直接接触 applyAction。

import 'team_card_script.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

export 'team_card_script.dart' show kTeamCardScript;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

/// 通过 Lua 状态机驱动团建卡牌房间的语义封装。
///
/// 用法：
/// ```dart
/// final handle = await TeamCardRoom.create(transport, playerSlots: 4, roles: [...]);
/// final engine = TeamCardRoom(handle);
/// await engine.ack();
/// await engine.deal();
/// ```
class TeamCardRoom {
  TeamCardRoom(this.handle);
  final RoomHandle handle;

  bool get isHost => handle.transport.deviceId.startsWith('host-');

  /// 准备就绪（ACK）
  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});

  /// 取消准备（UNACK）
  Future<void> unack() => handle.applyAction(type: 'UNACK', params: const {});

  /// 入座目标区（SIT）
  Future<void> sit({required String zone}) =>
      handle.applyAction(type: 'SIT', params: {'zone': zone});

  /// 房主发牌（DEAL）
  Future<void> deal() => handle.applyAction(type: 'DEAL', params: const {});

  /// 房主重置（RESET）
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});

  // ── 工厂方法 ──

  /// 创建房间（房主专用）
  static Future<RoomHandle> create(
    RelayV3Transport transport, {
    required int playerSlots,
    required int spectatorSlots,
    required List<Map<String, dynamic>> roles,
    String? alias,
  }) async {
    final h = await transport.createRoom(
      script: kTeamCardScript,
      initialParams: <String, dynamic>{
        'device_id': transport.deviceId,
        'alias': alias ?? transport.alias,
        'roles': roles,
        'player_slots': playerSlots,
        'spectator_slots': spectatorSlots,
      },
      maxPlayers: playerSlots + spectatorSlots,
    );
    return h;
  }

  /// 加入房间（玩家专用）
  static Future<RoomHandle> join(
    RelayV3Transport transport, {
    required String code,
  }) async {
    return transport.joinRoom(code: code);
  }
}

// ── Snapshot 便捷读取 ──

/// 从 Snapshot context 中安全提取字符串 map。
Map<String, String> extractStringMap(Snapshot? snap, String key) {
  final s = snap;
  if (s == null) return const {};
  final raw = s.context[key];
  if (raw is! Map) return const {};
  return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
}

/// 从 Snapshot context 中提取 int。
int extractInt(Snapshot? snap, String key) {
  final s = snap;
  return (s?.context[key] as num?)?.toInt() ?? 0;
}

/// 从 Snapshot context 中提取 String map（值可能是任意类型）。
Map<String, dynamic> extractDynamicMap(Snapshot? snap, String key) {
  final s = snap;
  if (s == null) return const {};
  final raw = s.context[key];
  if (raw is! Map) return const {};
  return raw.map((k, v) => MapEntry(k.toString(), v));
}

/// 从 Snapshot context 中提取 ready 状态。
Map<String, bool> extractReadyMap(Snapshot? snap) {
  final s = snap;
  if (s == null) return const {};
  final raw = s.context['ready'];
  if (raw is! Map) return const {};
  return raw.map((k, v) => MapEntry(k.toString(), v == true));
}

/// 获取某玩家的区。
String? myZone(Snapshot? snap, String deviceId) {
  final s = snap;
  if (s == null) return null;
  final raw = s.context['zones'];
  if (raw is! Map) return null;
  return raw[deviceId]?.toString();
}

/// 获取某玩家的角色身份（发牌后）。
String? myRole(Snapshot? snap, String deviceId) {
  final s = snap;
  if (s == null) return null;
  final a = s.context['assignments'];
  if (a is! Map) return null;
  return a[deviceId]?.toString();
}
