// lib/lab/demos/coup_lua/engine.dart
// 政变（Coup）Lua 版 — 网络动作封装 + Snapshot 便捷读取

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

import 'constants.dart';

export 'coup_script.dart' show kCoupScript;
export 'constants.dart';
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

/// 单个玩家状态（与服务端 context.players[did] 同构）。
class CoupPlayerState {
  final String deviceId;
  final String alias;
  final bool alive;
  final int coins;
  final String? card1; // 公开（你自己看自己的）/ null = 未发
  final String? card2;
  final bool card1Alive;
  final bool card2Alive;
  final int handCount; // 公开数（你死掉前都是 2；公开场景保留手数）
  final bool spectator; // 游戏中后加入者为观众

  const CoupPlayerState({
    required this.deviceId,
    required this.alias,
    required this.alive,
    required this.coins,
    required this.card1,
    required this.card2,
    required this.card1Alive,
    required this.card2Alive,
    required this.handCount,
    this.spectator = false,
  });

  factory CoupPlayerState.fromJson(String did, Map<dynamic, dynamic> j) {
    return CoupPlayerState(
      deviceId: did,
      alias: (j['alias'] ?? '').toString(),
      alive: j['alive'] == true,
      coins: (j['coins'] is num) ? (j['coins'] as num).toInt() : 0,
      card1: j['card1']?.toString(),
      card2: j['card2']?.toString(),
      card1Alive: j['card1_alive'] == true,
      card2Alive: j['card2_alive'] == true,
      handCount: (j['hand_count'] is num) ? (j['hand_count'] as num).toInt() : 0,
      spectator: j['spectator'] == true,
    );
  }
}

/// 当前进行中的动作（c.cur_action）。
class CoupCurrentAction {
  final CoupAction type;
  final String source; // 发起人 device_id
  final String? target;
  final CoupRole? claimerCard; // 当前声称的角色（质疑/反质疑针对）

  const CoupCurrentAction({
    required this.type,
    required this.source,
    this.target,
    this.claimerCard,
  });

  factory CoupCurrentAction.fromJson(Map<dynamic, dynamic> j) {
    final t = actionFromWire((j['type'] ?? '').toString());
    if (t == null) {
      throw FormatException('Unknown action type: ${j['type']}');
    }
    return CoupCurrentAction(
      type: t,
      source: (j['source'] ?? '').toString(),
      target: j['target']?.toString(),
      claimerCard: j['claimer_card'] == null
          ? null
          : roleFromWire(j['claimer_card'].toString()),
    );
  }

  bool get isBlockable {
    switch (type) {
      case CoupAction.foreignAid:
      case CoupAction.steal:
      case CoupAction.assassinate:
        return true;
      default:
        return false;
    }
  }
}

/// 政变房间 — 网络动作语义封装。
class CoupRoom {
  CoupRoom(this.handle);
  final RoomHandle handle;

  String get deviceId => handle.transport.deviceId;

  // ── 便捷 getter ──

  Snapshot? get snapshot => handle.latest;

  bool get isHost {
    final s = snapshot;
    if (s == null) return false;
    return s.context['host_id']?.toString() == deviceId;
  }

  /// 当前回合玩家 device_id（服务端 player_order + cur_player_idx 权威）。
  String? currentPlayerId(Snapshot? s) {
    if (s == null) return null;
    final order = s.context['player_order'];
    if (order is! List) return null;
    final idx = (s.context['cur_player_idx'] is num)
        ? (s.context['cur_player_idx'] as num).toInt()
        : 0;
    if (idx < 0 || idx >= order.length) return null;
    return order[idx]?.toString();
  }

  bool isMyTurn(Snapshot? s) => currentPlayerId(s) == deviceId;

  CoupPhase phase(Snapshot? s) {
    if (s == null) return CoupPhase.action;
    final raw = s.context['cur_phase']?.toString() ?? 'action';
    for (final p in CoupPhase.values) {
      if (p.name == raw) return p;
    }
    return CoupPhase.action;
  }

  Map<String, CoupPlayerState> players(Snapshot? s) {
    final raw = s?.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(
          k.toString(),
          CoupPlayerState.fromJson(k.toString(), v as Map),
        ));
  }

  CoupPlayerState? myPlayer(Snapshot? s) => players(s)[deviceId];

  CoupCurrentAction? currentAction(Snapshot? s) {
    final raw = s?.context['cur_action'];
    if (raw is! Map) return null;
    try {
      return CoupCurrentAction.fromJson(raw);
    } catch (_) {
      return null;
    }
  }

  List<String> playerOrder(Snapshot? s) {
    final raw = s?.context['player_order'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  String? winner(Snapshot? s) => s?.context['winner']?.toString();

  String? challenger(Snapshot? s) => s?.context['challenger']?.toString();

  /// 是否我是当前被质疑方（动作发起人 / 阻断人被质疑）
  bool isBeingChallenged(Snapshot? s) {
    if (s == null) return false;
    if (phase(s) != CoupPhase.reveal) return false;
    if (challenger(s) == null) return false;
    // 反质疑阻断时被质疑方是 blocker，否则是主动作发起人
    final revealer = blocker(s) ?? currentAction(s)?.source;
    return revealer != null && revealer == deviceId;
  }

  /// 当前我作为质疑方的目标（主动作发起人 或 反质疑期的阻断人）
  /// 返回 null = 现在不是质疑窗口
  ({String target, CoupRole claimRole})? myChallengeTarget(Snapshot? s) {
    final ph = phase(s);
    final ca = currentAction(s);
    if (ca == null) return null;
    if (ph == CoupPhase.challenge) {
      if (ca.source == deviceId) return null;
      if (ca.claimerCard == null) return null;
      return (target: ca.source, claimRole: ca.claimerCard!);
    }
    if (ph == CoupPhase.blockChallenge) {
      if (ca.source != deviceId) return null;
      final bl = blocker(s);
      if (bl == null || ca.claimerCard == null) return null;
      return (target: bl, claimRole: ca.claimerCard!);
    }
    return null;
  }

  String? blocker(Snapshot? s) => s?.context['blocker']?.toString();

  String? loser(Snapshot? s) => s?.context['loser']?.toString();

  /// 失卡原因：mainChallengerWrong / blockChallengerWrong / mainSourceWrong /
  /// blockFailed / effect
  String? loseReason(Snapshot? s) =>
      s?.context['lose_reason']?.toString();

  String? exchangePlayer(Snapshot? s) => s?.context['ex_player']?.toString();

  /// EXCHANGE 候选 4 张（从服务端读 raw list）。
  List<String> exchangeCards(Snapshot? s) {
    final raw = s?.context['exchange_cards'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).toList();
  }

  // ── 网络动作 ──

  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});
  Future<void> start() =>
      handle.applyAction(type: 'START', params: const {});
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});

  Future<void> act(CoupAction action, {String? target}) =>
      handle.applyAction(
        type: 'ACT',
        params: {
          'action_type': kCoupActionWire[action],
          if (target != null) 'target': target,
        },
      );

  Future<void> challenge(String target, CoupRole role) => handle.applyAction(
        type: 'CHALLENGE',
        params: {'target': target, 'claim_role': role.name},
      );

  Future<void> block(CoupRole blockerCard) => handle.applyAction(
        type: 'BLOCK',
        params: {'blocker_card': blockerCard.name},
      );

  Future<void> reveal(CoupRole role) => handle.applyAction(
        type: 'REVEAL',
        params: {'role': role.name},
      );

  Future<void> passResponse() => handle.applyAction(
        type: 'PASS_RESP',
        params: const {},
      );

  Future<void> loseCard(int slot) => handle.applyAction(
        type: 'LOSE_CARD',
        params: {'slot': slot},
      );

  Future<void> exchangeKeep(List<int> idxs) => handle.applyAction(
        type: 'EXCHANGE_KEEP',
        params: {'keep': idxs}, // 发数组，支持保留 1~2 张
      );
}