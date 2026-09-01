// lib/lab/demos/team_card/engine.dart
// 团建卡牌 — Lua 状态机封装 + 语义动作方法
//
// 三区（host/player/spectator）+ 主持人特权（看全部 + 私信）
//
// 提供：
//   - kTeamCardScript（从 team_card_script.dart 引用，脚本随本 demo 走）
//   - TeamCardRoom — 围绕 RoomHandle 的语义封装
//
// 调用方只用语义方法如 start(), reset(), setRolePool(), sit(), hostSend()，
// 不直接接触 applyAction。

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

import 'team_card_script.dart';

export 'team_card_script.dart' show kTeamCardScript;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

/// 通过 Lua 状态机驱动团建卡牌房间的语义封装。
///
/// 生命周期：create → state="setup"（房主配置）→ open() → "lobby"
/// → start()（玩家区满）→ "playing" → reset() → "lobby"。
///
/// 用法（社交房间号模式）：
/// ```dart
/// final t = RelayV3Transport(relayUrl: ..., alias: 'Alice', deviceId: <stable>);
/// final handle = await TeamCardRoom.tryJoinOrCreate(t, code: '666666');
/// final engine = TeamCardRoom(handle);
/// if (myIsHost(handle.latest, t.deviceId)) {
///   await engine.setPlayerSlots(playerSlots: 3);
///   await engine.setRolePool(roles: [...]);
///   await engine.open();   // waiting 玩家自动入座，state=lobby
/// }
/// await engine.start();    // 玩家区满时发牌
/// ```
class TeamCardRoom {
  TeamCardRoom(this.handle);
  final RoomHandle handle;

  /// 当前 device id（在 transport 里）
  String get myDeviceId => handle.transport.deviceId;

  /// 房主开放房间（setup → lobby；waiting 集中入座）
  Future<void> open() => handle.applyAction(type: 'OPEN', params: const {});

  /// 房主设置玩家区/旁观区容量（setup + lobby；lobby 带人数保护）
  Future<void> setPlayerSlots({
    required int playerSlots,
    int spectatorSlots = 0,
  }) =>
      handle.applyAction(type: 'SET_PLAYER_SLOTS', params: {
        'player_slots': playerSlots,
        'spectator_slots': spectatorSlots,
      });

  /// 房主上传/更新身份池（setup + lobby）
  Future<void> setRolePool({required List<Map<String, dynamic>> roles}) =>
      handle.applyAction(type: 'SET_ROLE_POOL', params: {'roles': roles});

  /// 房主一键发牌（lobby + 玩家区满）
  Future<void> start() => handle.applyAction(type: 'START', params: const {});

  /// 房主重置（playing → lobby，连续开局）
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});

  /// 换区（lobby 阶段）。`zone` ∈ {'host','player','spectator'}。
  Future<void> sit({required String zone}) =>
      handle.applyAction(type: 'SIT', params: {'zone': zone});

  /// 主持人给指定玩家发私信（playing）
  Future<void> hostSend({required String to, required String text}) =>
      handle.applyAction(
        type: 'HOST_MSG',
        params: {'to': to, 'text': text},
      );

  // ── 工厂方法 ──

  /// 社交房间号模式：第一个输入未存在房间号的人自动成为房主（host），
  /// 房间创建后 state="setup"（其他加入者 waiting 排队），房主 open() 后才入座。
  ///
  /// 房间总人数上限（默认 8，三区总和）由 Lua on_join 强制——
  /// 后端 transport 不查 max_players，但创建时仍如实上报。
  static Future<RoomHandle> tryJoinOrCreate(
    RelayV3Transport transport, {
    required String code,
    int maxPlayers = 8,
    String? alias,
  }) async {
    final params = <String, dynamic>{
      'device_id': transport.deviceId,
      'alias': alias ?? transport.alias,
      'max_players': maxPlayers,
    };
    return transport.tryJoinOrCreate(
      code: code,
      script: kTeamCardScript,
      initialParams: params,
      maxPlayers: maxPlayers,
    );
  }
}

// ── Snapshot 便捷读取（服务端权威） ──

/// 房主 device_id（来自 snapshot.context['host_id']）
String? hostIdOf(Snapshot? snap) {
  final s = snap;
  if (s == null) return null;
  return s.context['host_id']?.toString();
}

/// 当前 deviceId 是否为房主（**唯一可信的房主判定方式**，禁止客户端自查）
bool myIsHost(Snapshot? snap, String deviceId) {
  final h = hostIdOf(snap);
  return h != null && h == deviceId;
}

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

/// 读取主持人私信列表（list of {from, to, text, at}）
List<Map<String, dynamic>> extractHostMessages(Snapshot? snap) {
  final s = snap;
  if (s == null) return const [];
  final raw = s.context['host_messages'];
  if (raw is! List) return const [];
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

/// 筛选当前 deviceId 收到的私信（to == myDeviceId）
List<Map<String, dynamic>> myHostMessages(Snapshot? snap, String deviceId) {
  return extractHostMessages(snap)
      .where((m) => m['to'] == deviceId)
      .toList();
}

/// 获取某玩家的区（host/player/spectator/null）。
String? myZone(Snapshot? snap, String deviceId) {
  final s = snap;
  if (s == null) return null;
  final raw = s.context['zones'];
  if (raw is! Map) return null;
  return raw[deviceId]?.toString();
}

/// 获取某玩家的角色身份（发牌后）。注意：只有自己/或主持人视角能读到值；
/// 其他玩家的 assignments 在协议层禁止下发（防止作弊）。
String? myRole(Snapshot? snap, String deviceId) {
  final s = snap;
  if (s == null) return null;
  final a = s.context['assignments'];
  if (a is! Map) return null;
  return a[deviceId]?.toString();
}