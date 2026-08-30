// lib/core/chess/p2p/chess_net.dart
//
// 国际象棋 P2P 网络动作封装 + Snapshot 便捷读取（v2：READY 门 + 断连等重连）。
//
// 与 jungle_chess_lua/jungle_engine.dart / tetris_lua/engine.dart 中
// [TetrisRoom]/[JungleRoom] 同构：
//   · 网络动作封装（ack / deal / start / move / resign / drawOffer...）
//   · Snapshot 静态读取（hostId / readyMap / disconnectedPlayers / isHost / isGuest）
//
// 设计要点：
//   - 服务端权威字段：host_id / guest_id / players / ready / disconnected /
//     fen / moves / status / winner / action_permissions
//   - 角色判定：服务端 action_permissions["..."] 配合 isHost/isGuest 推导
//   - 不动 lib/core/chess/engine/ 下的纯规则引擎（ChessEngine / make_move /
//     fen_codec 等 —— 那些是"本地走法生成器"，与网络无关）
//
// 走法（UCI + FEN）走 dart 侧 [ChessEngine] 计算（kChessScript 服务端只
// 做结构 + 归属 + 轮次 fence，不验合法性）。

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

export 'chess_script.dart' show kChessScript;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

// ══════════════════════════════════════════════════════════════
// 网络动作的语义封装
// ══════════════════════════════════════════════════════════════

/// 国际象棋互联网对战的网络动作封装（语义层）。
class ChessRoom {
  ChessRoom(this.handle);
  final RoomHandle handle;

  String get deviceId => handle.transport.deviceId;

  // ── 角色（读服务端快照）──

  /// 我是房主（host / 白方）吗？null = 尚未收到快照。
  bool? get isHostMaybe {
    final s = handle.latest;
    if (s == null) return null;
    final hid = s.context['host_id']?.toString();
    if (hid == null || hid.isEmpty) return null;
    return deviceId == hid;
  }

  /// 我是 guest（黑方）吗？
  bool? get isGuestMaybe {
    final s = handle.latest;
    if (s == null) return null;
    final gid = s.context['guest_id']?.toString();
    if (gid == null || gid.isEmpty) return null;
    return deviceId == gid;
  }

  // ── 网络动作 ──

  /// 准备（lobby 阶段点"准备好了" → on_action_ACK）。
  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});

  /// 开始对弈（host 在 ready 阶段点"开始游戏"）。
  /// 优先 DEAL（语义清晰）；START 兼容旧客户端 / 旧 lobby UI。
  Future<void> deal() => handle.applyAction(type: 'DEAL', params: const {});

  /// 同 deal，type 走 START（向后兼容 —— 旧 lobby / 旧版 relay widget）。
  Future<void> start() => handle.applyAction(type: 'START', params: const {});

  /// 走法（MOVE）。uci + fen 由调用方用 [ChessEngine] 计算后传入；
  /// ts 是客户端本地时间戳，服务端仅记录。
  Future<void> move({
    required String uci,
    required String fen,
    int? ts,
  }) =>
      handle.applyAction(
        type: 'MOVE',
        params: {
          'uci': uci,
          'fen': fen,
          'ts': ts,
        },
      );

  /// 投降（RESIGN）。
  Future<void> resign() =>
      handle.applyAction(type: 'RESIGN', params: const {});

  /// 议和申请。对方已挂 offer → 直接发 DRAW_ACCEPT → 和棋。
  /// 调用方应读 [ChessRoom.opponentOffered] 决定传 DRAW_OFFER 还是 DRAW_ACCEPT。
  Future<void> drawOffer() =>
      handle.applyAction(type: 'DRAW_OFFER', params: const {});
  Future<void> drawAccept() =>
      handle.applyAction(type: 'DRAW_ACCEPT', params: const {});
  Future<void> drawDecline() =>
      handle.applyAction(type: 'DRAW_DECLINE', params: const {});

  /// 终局声明（走子方引擎检测到 checkmate / stalemate 后上报）。
  Future<void> claimEnd({required String reason}) =>
      handle.applyAction(type: 'CLAIM_END', params: {'reason': reason});

  /// 重开（host only，ended → lobby；双方需重新 ACK）。
  Future<void> reset() =>
      handle.applyAction(type: 'RESET', params: const {});

  // ── Snapshot 便捷读取（静态，便于 UI 无实例调用）──

  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  static String? guestId(Snapshot? s) => s?.context['guest_id']?.toString();

  static Map<String, String> players(Snapshot? s) {
    final raw = s?.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 双方"准备"状态映射（device_id → 是否已 ACK）。lobby/ready 阶段使用。
  static Map<String, bool> readyMap(Snapshot? s) {
    final raw = s?.context['ready'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v == true));
  }

  /// 离线玩家表（断线但保留在 players 中的玩家，UI 用于显示"对手掉线"标记；
  /// on_join 时若同 device_id 自动清掉）。
  static Map<String, bool> disconnectedPlayers(Snapshot? s) {
    final raw = s?.context['disconnected'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v == true));
  }

  /// 当前棋盘 FEN（服务端权威）。
  static String? fen(Snapshot? s) => s?.context['fen']?.toString();

  /// 当前对局状态（"playing" / "check" / "checkmate" / ...）。
  static String status(Snapshot? s) =>
      s?.context['status']?.toString() ?? 'playing';

  /// 终局胜方 device_id（仅 terminal 状态有值；和棋/僵局为 null）。
  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  /// 棋谱（服务端权威）。
  static List<Map<String, dynamic>> moves(Snapshot? s) {
    final raw = s?.context['moves'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// 挂起的议和 offer（device_id → true）。
  static Map<String, bool> drawOffers(Snapshot? s) {
    final raw = s?.context['draw_offers'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v == true));
  }

  static Map<String, String> actionPermissions(Snapshot? s) {
    final raw = s?.context['action_permissions'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 我能不能发这个 action？读服务端 action_permissions + 角色判定。
  ///
  /// chess 的 current_player 由服务端 moves 奇偶推（v1 与 v2 一致）：
  ///   moves 偶数 → 轮白（host）走；奇数 → 轮黑（guest）走。
  static bool canPerform(
    String action,
    Snapshot? snap, {
    required bool isHost,
  }) {
    final rule = actionPermissions(snap)[action];
    if (rule == null || rule == 'any') return true;
    if (rule == 'host') return isHost;
    if (rule == 'current_player') {
      final n = (snap?.context['moves'] is List)
          ? (snap!.context['moves'] as List).length
          : 0;
      // n 偶数 → 轮白走 → host；奇数 → 轮黑走 → guest
      return (n.isEven && isHost) || (n.isOdd && !isHost);
    }
    if (rule == 'non_current_player') {
      final n = (snap?.context['moves'] is List)
          ? (snap?.context['moves'] as List).length
          : 0;
      // 刚走完的一方：n 偶数 → 白刚走完 → 黑声明 CLAIM_END
      return (n.isEven && !isHost) || (n.isOdd && isHost);
    }
    return false;
  }

  /// 我是 host / guest 的便捷判别（带 null 兜底：未收到快照 / 身份尚未判定
  /// 时回退 false，UI 应另行处理"无角色"态）。
  static bool isHost(Snapshot? s, String myId) {
    final hid = hostId(s);
    return hid != null && hid.isNotEmpty && hid == myId;
  }

  static bool isGuest(Snapshot? s, String myId) {
    final gid = guestId(s);
    return gid != null && gid.isNotEmpty && gid == myId;
  }
}
