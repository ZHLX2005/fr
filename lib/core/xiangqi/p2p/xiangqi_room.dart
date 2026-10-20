// lib/core/xiangqi/p2p/xiangqi_room.dart
//
// XiangqiRoom —— RoomHandle（relay v3）的象棋语义封装。
//
// 职责（对齐 draughts_room.dart 的 DraughtsRoom）：
//   · 把 applyAction 包成领域动作：ack / deal / move / resign / undo /
//     offerDraw / declareEnd / reset
//   · 从 Snapshot.context 解析服务端权威字段（players / ready / moves / status…）
//   · 用棋子引擎把 moves 重放成 XiangqiBoardState（供 UI 渲染 + 本地终局判定）
//
// 与服务端的分工：relay 只追加棋谱 + 校验记号结构与轮次；
// **终局由客户端引擎判定后 CLAIM_END 上报**（与 chess / draughts 同模式）。
//
// 与 DraughtsRoom 的差异：
//   · 颜色是「红 / 黑」（XiangqiColor），hostColor 取值 'r' / 'b'。
//   · 走法记号是 `b0e2`（XiangqiMove.fromUci），不是 PDN。
//   · 局面串是中国象棋 FEN（10 段 + 轮次 'r'/'b'）。

import '../constants/xiangqi_constants.dart';
import '../engine/fen_codec.dart';
import '../engine/make_move.dart';
import '../engine/xiangqi_engine.dart';
import '../models/board_state.dart';
import '../models/game_status.dart';
import '../models/move.dart';
import '../models/piece.dart';
import '../../net_engine/relay_v3/relay_v3_transport.dart';

export '../../net_engine/relay_v3/relay_v3_transport.dart'
    show RoomHandle, Snapshot, RelayV3Exception, WSCloseEvent, WSCloseCode;

/// 一条服务端棋谱记录
class XiangqiMoveRecord {
  /// 走法记号（`b0e2`）
  final String uci;

  /// 走子方 device_id
  final String by;

  /// 时间戳（ms）
  final int ts;

  /// 走完后的局面 FEN
  final String fen;

  const XiangqiMoveRecord({
    required this.uci,
    required this.by,
    required this.ts,
    required this.fen,
  });

  static XiangqiMoveRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final uci = raw['uci']?.toString();
    if (uci == null || uci.isEmpty) return null;
    return XiangqiMoveRecord(
      uci: uci,
      by: raw['by']?.toString() ?? '',
      ts: (raw['ts'] as num?)?.toInt() ?? 0,
      fen: raw['fen']?.toString() ?? '',
    );
  }
}

/// 重放结果：局面 + 是否与服务端权威局面一致。
class XiangqiReplayResult {
  /// 重放（必要时修复）后的棋盘状态。
  final XiangqiBoardState board;

  /// 全程无需修复（每手都能正常重放）。
  final bool consistent;

  /// 首次发生「无法重放 / 与服务端不一致」的手数（null = 全程一致）。
  ///
  /// 该手之后的位置取自服务端上报的 FEN（协议里的权威事实来源），
  /// 因此棋盘**与服务端对齐**，只是这一手被本地引擎判为不合法。
  final int? repairedAtPly;

  /// 最终棋盘是否与服务端 `c.fen` 完全一致（局面 + 轮次）。
  ///
  /// 检测到不一致时会把棋盘**改为服务端局面**，故修复后恒为 true；
  /// 只有服务端 FEN 本身无法解析时才是 false。
  final bool matchesServerFen;

  const XiangqiReplayResult({
    required this.board,
    required this.consistent,
    required this.repairedAtPly,
    required this.matchesServerFen,
  });
}

/// 中国象棋房间封装
class XiangqiRoom {
  final RoomHandle handle;

  XiangqiRoom(this.handle);

  String get deviceId => handle.transport.deviceId;

  // ── 动作 ──

  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});

  Future<void> deal() => handle.applyAction(type: 'DEAL', params: const {});

  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});

  /// 准备阶段改规则（SET_RULES）—— 仅 host、仅 lobby/ready；
  /// 服务端改完清 ready、回 lobby。[hostColor] ∈ 'r' / 'b' / 'random'。
  Future<void> setRules({String? hostColor}) {
    final params = <String, dynamic>{};
    if (hostColor != null) params['host_color'] = hostColor;
    return handle.applyAction(type: 'SET_RULES', params: params);
  }

  /// 认输
  Future<void> resign() => handle.applyAction(type: 'RESIGN', params: const {});

  /// 求和（发起）
  Future<void> offerDraw() =>
      handle.applyAction(type: 'DRAW_OFFER', params: const {});

  /// 接受对方的求和 → 双方和棋终局
  Future<void> acceptDraw() =>
      handle.applyAction(type: 'DRAW_ACCEPT', params: const {});

  /// 拒绝对方的求和
  Future<void> declineDraw() =>
      handle.applyAction(type: 'DRAW_DECLINE', params: const {});

  /// 悔棋：申请（只挂 offer，等对方接受）。
  Future<void> undoOffer() =>
      handle.applyAction(type: 'UNDO_OFFER', params: const {});

  /// 接受对方的悔棋申请 → 服务端 pop 1~2 手回退棋谱。
  Future<void> undoAccept() =>
      handle.applyAction(type: 'UNDO_ACCEPT', params: const {});

  /// 拒绝对方的悔棋申请。
  Future<void> undoDecline() =>
      handle.applyAction(type: 'UNDO_DECLINE', params: const {});

  /// 走子：只上报记号 + 走后 FEN（服务端做结构校验与轮次反证）
  Future<void> move(XiangqiMove move, XiangqiBoardState nextState) =>
      handle.applyAction(type: 'MOVE', params: {
        'uci': move.toUci(),
        'fen': fenFromBoardState(nextState),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });

  /// 声明终局（reason 取 XiangqiEndReason 的 name：checkmate / stalemate）
  Future<void> declareEnd(String reason) =>
      handle.applyAction(type: 'CLAIM_END', params: {'reason': reason});

  // ── 快照解析（服务端权威字段）──

  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  static String? guestId(Snapshot? s) => s?.context['guest_id']?.toString();

  /// host 执子色：'r'（红）/ 'b'（黑）
  static XiangqiColor hostColor(Snapshot? s) {
    final raw = s?.context['host_color']?.toString();
    return raw == 'b' ? XiangqiColor.black : XiangqiColor.red;
  }

  /// 我执的子色（依据 host/guest 身份推）
  static XiangqiColor myColor(RoomHandle handle, Snapshot? s) {
    final me = handle.transport.deviceId;
    final hc = hostColor(s);
    if (me == hostId(s)) return hc;
    return xiangqiOpposite(hc);
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

  /// 挂起的悔棋申请（device_id → true）。
  static Map<String, bool> undoOffers(Snapshot? s) {
    final raw = s?.context['undo_offers'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries) e.key.toString(): e.value == true,
    };
  }

  /// 挂起的求和申请（device_id → true）。
  static Map<String, bool> drawOffers(Snapshot? s) {
    final raw = s?.context['draw_offers'];
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

  /// 服务端权威的 action 权限表（action → 规则词）。
  ///
  /// 表由 Lua `on_init` 的 `c.action_permissions` 维护（服务端权威），
  /// 客户端只读不改 —— 见 relay-lua-state-machine skill 的 A03 ref。
  static Map<String, String> actionPermissions(Snapshot? s) {
    final raw = s?.context['action_permissions'];
    if (raw is! Map) return const {};
    return {
      for (final e in raw.entries) e.key.toString(): e.value.toString(),
    };
  }

  /// 我能不能发这个 action？读服务端 action_permissions + 角色判定。
  ///
  /// current_player 由「先手方 + 手数奇偶」推（与 Lua `side_to_move` 同源）：
  ///   n 偶数 → 轮先手方；n 奇数 → 轮后手方。
  /// 先手方 = host_color == initial_side 的一方 —— host 未必先手
  /// （host 执黑 / 黑先残局），故不能硬编码「n 偶 → 轮 host」。
  ///
  /// UI 的按钮 enable / 显示**全走本方法**，零特判代码（对齐 gomoku / reversi /
  /// jungle / chess 的同款 helper）。
  static bool canPerform(
    String action,
    Snapshot? snap, {
    required bool isHost,
  }) {
    final rule = actionPermissions(snap)[action];
    if (rule == null || rule == 'any') return true;
    if (rule == 'host') return isHost;
    if (rule == 'current_player' || rule == 'non_current_player') {
      final n = (snap?.context['moves'] is List)
          ? (snap!.context['moves'] as List).length
          : 0;
      final hostIsFirst = hostColor(snap) == initialSide(snap);
      final iAmFirst = isHost == hostIsFirst;
      final isMyTurn = (n.isEven == iAmFirst);
      return rule == 'current_player' ? isMyTurn : !isMyTurn;
    }
    return false;
  }

  /// 我是 host / guest 的便捷判别（带 null 兜底：未收到快照 / 身份尚未判定
  /// 时回退 false，UI 应另行处理「无角色」态）。
  static bool isHost(Snapshot? s, String myId) {
    final hid = hostId(s);
    return hid != null && hid.isNotEmpty && hid == myId;
  }

  static bool isGuest(Snapshot? s, String myId) {
    final gid = guestId(s);
    return gid != null && gid.isNotEmpty && gid == myId;
  }

  static String? status(Snapshot? s) => s?.context['status']?.toString();

  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  static String? endReason(Snapshot? s) =>
      s?.context['end_reason']?.toString();

  /// 当前 FEN（服务端权威局面串）
  static String? fen(Snapshot? s) => s?.context['fen']?.toString();

  /// 初始 FEN（重放起点）
  static String initialFen(Snapshot? s) =>
      s?.context['initial_fen']?.toString() ?? kXiangqiStartingFen;

  static String? endgameLabel(Snapshot? s) =>
      s?.context['endgame_label']?.toString();

  /// 谁先手：'r'（红）/ 'b'（黑）
  static XiangqiColor initialSide(Snapshot? s) =>
      s?.context['initial_side']?.toString() == 'b'
          ? XiangqiColor.black
          : XiangqiColor.red;

  static List<XiangqiMoveRecord> rebuildHistory(Snapshot? s) {
    final raw = s?.context['moves'];
    if (raw is! List) return const [];
    // 空感知元素(?expr)语法 analyzer 6.x 解析不了（hive_generator 锁死），改等价写法
    final records = <XiangqiMoveRecord>[];
    for (final e in raw) {
      final rec = XiangqiMoveRecord.fromJson(e);
      if (rec != null) records.add(rec);
    }
    return records;
  }

  /// 用引擎把棋谱重放成棋盘状态（服务端只存记号，不存局面）。
  ///
  /// ⚠ 只做**结构**重放（起点有子 / 终点非己方子），不逐手做规则校验 ——
  ///   逐手规则校验很贵（每手一次全量走法生成），而最终与服务端 `c.fen`
  ///   的交叉核对是等价且**便宜**的兜底（见 [rebuildBoardVerified]）。
  static XiangqiBoardState rebuildBoard(
    List<XiangqiMoveRecord> history, {
    String initialFen = kXiangqiStartingFen,
    XiangqiColor? fallbackSide,
  }) {
    return rebuildBoardVerified(
      history,
      initialFen: initialFen,
      initialSide: fallbackSide,
    ).board;
  }

  /// **可核对**的棋谱重放 —— 服务端权威优先。
  ///
  /// 为什么需要它：服务端只校验走法记号的**形状**（不做象棋规则推理），
  /// 而客户端把 `c.moves` 当权威棋谱重放。若某手在本地**无法重放**
  /// （记号非法 / 起点无子 / 终点是己方子 —— 正常对局不会出现，异常客户端
  /// 或引擎分歧会出现），旧实现会**静默跳过**该手：
  ///   · 客户端棋盘与服务端 `c.fen` 分叉；
  ///   · 棋盘回合（按局面推）与权限表回合（按手数奇偶推）判反 →
  ///     AND 门把**双方**都锁死 → 对局彻底卡死且毫无提示。
  ///
  /// 本方法做三件事：
  ///   1. 逐手结构校验；遇到无法重放的手 → **不静默跳过**，改用该手之后
  ///      服务端上报的 FEN（权威事实）把棋盘对齐到服务端，并记录
  ///      [XiangqiReplayResult.repairedAtPly]。
  ///   2. 先手方以服务端 `initial_side` 为准（与 Lua `side_to_move` 同源），
  ///      不依赖初始 FEN 的轮次字段（残局 / 自定义开局时二者可能不一致）。
  ///   3. 最终与服务端 `c.fen` 交叉核对；不一致则以服务端为准。
  static XiangqiReplayResult rebuildBoardVerified(
    List<XiangqiMoveRecord> history, {
    String initialFen = kXiangqiStartingFen,
    String? serverFen,
    XiangqiColor? initialSide,
  }) {
    var state = _boardStateOrNull(initialFen) ?? XiangqiBoardState.initial();
    // 先手方以服务端 initial_side 为准（**不能**只看 FEN 轮次字段 ——
    // 残局 / 自定义开局时二者可能不一致 → 棋盘回合整体反转）。
    if (initialSide != null) {
      state = state.copyWith(sideToMove: initialSide);
    }

    int? repairedAt;
    for (var i = 0; i < history.length; i++) {
      final rec = history[i];
      final move = XiangqiMove.fromUci(rec.uci);
      if (move == null) {
        repairedAt ??= i;
        final repaired = _boardStateOrNull(rec.fen);
        if (repaired == null) break;
        state = repaired;
        continue;
      }
      try {
        state = applyXiangqiMoveSimple(state, move);
      } catch (_) {
        // 无法重放（起点无子 / 终点己方子）→ 用服务端该手后的 FEN 对齐。
        repairedAt ??= i;
        final repaired = _boardStateOrNull(rec.fen);
        if (repaired == null) break;
        state = repaired;
      }
    }

    // 与服务端 c.fen 交叉核对（最终兜底）：不一致 → **以服务端为准**。
    // 修复后棋盘即与服务端一致，故 matchesServerFen 仍为 true；
    // 只有服务端 FEN 本身不可解析时才是 false。
    var matchesServerFen = true;
    if (serverFen != null && serverFen.isNotEmpty) {
      final serverState = _boardStateOrNull(serverFen);
      if (serverState == null) {
        matchesServerFen = false;
      } else if (serverState.positionKey != state.positionKey) {
        repairedAt ??= history.length;
        state = serverState;
      }
    }

    return XiangqiReplayResult(
      board: state,
      consistent: repairedAt == null,
      repairedAtPly: repairedAt,
      matchesServerFen: matchesServerFen,
    );
  }

  /// 解析 FEN → 棋盘；非法 FEN 返回 null（不抛）。
  static XiangqiBoardState? _boardStateOrNull(String fen) {
    if (fen.isEmpty) return null;
    try {
      return boardStateFromFen(fen);
    } catch (_) {
      return null;
    }
  }

  /// 全部局面键（含起点）—— 供重复局面检测（象棋一般不强制和棋，保留接口平行）
  static List<String> rebuildPositionHistory(
    List<XiangqiMoveRecord> history, {
    String initialFen = kXiangqiStartingFen,
  }) {
    var state = boardStateFromFen(initialFen);
    final keys = <String>[state.positionKey];
    for (final rec in history) {
      final move = XiangqiMove.fromUci(rec.uci);
      if (move == null) continue;
      try {
        state = applyXiangqiMoveSimple(state, move);
      } catch (_) {
        continue;
      }
      keys.add(state.positionKey);
    }
    return keys;
  }

  /// 当前轮次方（由棋谱重放后的状态给）
  static XiangqiColor currentSide(XiangqiBoardState state) => state.sideToMove;

  /// 本地引擎判定当前终局（供 CLAIM_END 上报）
  static XiangqiStatus checkStatus(
    XiangqiBoardState state,
    List<String> history,
  ) =>
      kDefaultXiangqiEngine.status(state, positionHistory: history);
}
