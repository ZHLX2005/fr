// lib/core/draughts/p2p/draughts_room.dart
//
// DraughtsRoom —— RoomHandle（relay v3）的跳棋语义封装。
//
// 职责（对齐 jungle_chess_lua 的 JungleRoom）：
//   · 把 applyAction 包成领域动作：ack / deal / move / resign / reset / declareEnd
//   · 从 Snapshot.context 解析服务端权威字段（players / ready / moves / status…）
//   · 用棋子引擎把 moves 重放成 DraughtsBoardState（供 UI 渲染 + 本地终局判定）
//
// 与服务端的分工：relay 只追加棋谱 + 校验 PDN 结构与轮次；
// **终局由客户端引擎判定后 CLAIM_END 上报**（与 chess_v5 同模式）。

import '../constants/draughts_constants.dart';
import '../engine/draughts_engine.dart';
import '../engine/make_move.dart';
import '../engine/pdn_codec.dart';
import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../../net_engine/relay_v3/relay_v3_transport.dart';

export '../../net_engine/relay_v3/relay_v3_transport.dart'
    show RoomHandle, Snapshot;

/// 一条服务端棋谱记录
class DraughtsMoveRecord {
  final String pdn;
  final String by;
  final int ts;
  final String fen;

  const DraughtsMoveRecord({
    required this.pdn,
    required this.by,
    required this.ts,
    required this.fen,
  });

  static DraughtsMoveRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final pdn = raw['pdn']?.toString();
    if (pdn == null || pdn.isEmpty) return null;
    return DraughtsMoveRecord(
      pdn: pdn,
      by: raw['by']?.toString() ?? '',
      ts: (raw['ts'] as num?)?.toInt() ?? 0,
      fen: raw['fen']?.toString() ?? '',
    );
  }
}

/// 跳棋房间封装
class DraughtsRoom {
  final RoomHandle handle;

  DraughtsRoom(this.handle);

  String get deviceId => handle.transport.deviceId;

  // ── 动作 ──

  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});

  Future<void> deal() => handle.applyAction(type: 'DEAL', params: const {});

  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});

  /// 准备阶段改规则（SET_RULES）—— 仅 host、仅 lobby/ready；
  /// 服务端改完清 ready、回 lobby。[hostColor] ∈ 'w' / 'b' / 'random'。
  Future<void> setRules({String? hostColor}) {
    final params = <String, dynamic>{};
    if (hostColor != null) params['host_color'] = hostColor;
    return handle.applyAction(type: 'SET_RULES', params: params);
  }

  Future<void> resign() => handle.applyAction(type: 'RESIGN', params: const {});

  Future<void> offerDraw() =>
      handle.applyAction(type: 'DRAW_OFFER', params: const {});

  Future<void> acceptDraw() =>
      handle.applyAction(type: 'DRAW_ACCEPT', params: const {});

  Future<void> declineDraw() =>
      handle.applyAction(type: 'DRAW_DECLINE', params: const {});

  /// 走子：只上报 PDN + 走后 FEN（服务端做结构校验与轮次反证）
  Future<void> move(DraughtsMove m, DraughtsBoardState nextState) =>
      handle.applyAction(type: 'MOVE', params: {
        'pdn': m.toPdn(),
        'fen': fenFromBoardState(nextState),
      });

  /// 声明终局（reason 取 DraughtsEndReason 的 name：noPieces / noMoves /
  /// threefold / kingVsKing / kingMoveLimit）
  Future<void> declareEnd(String reason) =>
      handle.applyAction(type: 'CLAIM_END', params: {'reason': reason});

  // ── 快照解析（服务端权威字段）──

  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  static String? guestId(Snapshot? s) => s?.context['guest_id']?.toString();

  /// host 执子色：'w' / 'b'
  static DraughtsColor hostColor(Snapshot? s) {
    final raw = s?.context['host_color']?.toString();
    return raw == 'b' ? DraughtsColor.black : DraughtsColor.white;
  }

  /// 我执的子色（依据 host/guest 身份推）
  static DraughtsColor myColor(RoomHandle handle, Snapshot? s) {
    final me = handle.transport.deviceId;
    final hc = hostColor(s);
    if (me == hostId(s)) return hc;
    return draughtsOpposite(hc);
  }

  static Map<String, String> players(Snapshot? s) {
    final raw = s?.context['players'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries) e.key.toString(): e.value?.toString() ?? '',
    };
  }

  static Map<String, bool> readyMap(Snapshot? s) {
    final raw = s?.context['ready'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries) e.key.toString(): e.value == true,
    };
  }

  static Map<String, bool> disconnectedPlayers(Snapshot? s) {
    final raw = s?.context['disconnected'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries) e.key.toString(): e.value == true,
    };
  }

  static String? status(Snapshot? s) => s?.context['status']?.toString();

  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  static String? endReason(Snapshot? s) =>
      s?.context['end_reason']?.toString();

  /// 当前 FEN（服务端权威局面串）
  static String? fen(Snapshot? s) => s?.context['fen']?.toString();

  /// 初始 FEN（重放起点）
  static String initialFen(Snapshot? s) =>
      s?.context['initial_fen']?.toString() ?? kDraughtsStartingFen;

  static String? endgameLabel(Snapshot? s) =>
      s?.context['endgame_label']?.toString();

  /// 谁先手：'w' / 'b'
  static DraughtsColor initialSide(Snapshot? s) =>
      s?.context['initial_side']?.toString() == 'b'
          ? DraughtsColor.black
          : DraughtsColor.white;

  static List<DraughtsMoveRecord> rebuildHistory(Snapshot? s) {
    final raw = s?.context['moves'];
    if (raw is! List) return const [];
    return [
      for (final e in raw) ?DraughtsMoveRecord.fromJson(e),
    ];
  }

  /// 用引擎把棋谱重放成棋盘状态（服务端只存 PDN，不存局面）。
  static DraughtsBoardState rebuildBoard(
    List<DraughtsMoveRecord> history, {
    String initialFen = kDraughtsStartingFen,
    DraughtsColor? fallbackSide,
  }) {
    var state = boardStateFromFen(initialFen);
    if (fallbackSide != null && state.sideToMove != fallbackSide &&
        history.isEmpty) {
      state = state.copyWith(sideToMove: fallbackSide);
    }
    for (final rec in history) {
      final move = pdnMoveToMove(state, rec.pdn);
      if (move == null) continue; // 坏记录跳过，不拖垮整盘
      state = applyMoveSimple(state, move);
    }
    return state;
  }

  /// 全部局面键（含起点）—— 供三次重复判定
  static List<String> rebuildPositionHistory(
    List<DraughtsMoveRecord> history, {
    String initialFen = kDraughtsStartingFen,
  }) {
    var state = boardStateFromFen(initialFen);
    final keys = <String>[state.positionKey];
    for (final rec in history) {
      final move = pdnMoveToMove(state, rec.pdn);
      if (move == null) continue;
      state = applyMoveSimple(state, move);
      keys.add(state.positionKey);
    }
    return keys;
  }

  /// 当前轮次方（由棋谱重放后的状态给）
  static DraughtsColor currentSide(DraughtsBoardState state) =>
      state.sideToMove;

  /// 服务端是否允许某动作（action_permissions 镜像）
  static bool canPerform(Snapshot? s, String action) {
    final raw = s?.context['action_permissions'];
    if (raw is! Map) return true;
    final rule = raw[action]?.toString();
    if (rule == null || rule == 'any') return true;
    // 细粒度角色判定在 UI 层用 host/current 身份补；此处只做"是否声明"。
    return true;
  }

  /// 本地引擎判定当前终局（供 CLAIM_END 上报）
  static DraughtsStatus checkStatus(DraughtsBoardState state, List<String> history) =>
      kDefaultDraughtsEngine.status(state, positionHistory: history);
}
