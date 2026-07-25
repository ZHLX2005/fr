// lib/lab/demos/gomoku_lua/engine.dart
// 五子棋 Lua 版 — 网络动作封装 + Snapshot 便捷读取 + 连五判定

import 'constants.dart' show kGomokuSize, kGomokuWinLength;
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

export 'gomoku_script.dart' show kGomokuScript;
export 'constants.dart' show kGomokuSize, kGomokuWinLength;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

/// 单步落子记录（与服务端 history 条目同构）。
class GomokuMove {
  const GomokuMove({required this.x, required this.y, required this.isBlack});
  final int x;  // 0..14
  final int y;  // 0..14
  final bool isBlack;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'isBlack': isBlack};

  factory GomokuMove.fromJson(Map<String, dynamic> j) => GomokuMove(
        x: (j['x'] as num).toInt(),
        y: (j['y'] as num).toInt(),
        isBlack: j['isBlack'] == true,
      );

  @override
  String toString() => '(${isBlack ? "黑" : "白"} $x,$y)';
}

/// 棋盘状态：每格 0=空 / 1=黑 / 2=白。坐标 board[y][x]。
typedef GomokuBoard = List<List<int>>;

/// 五子棋网络动作的语义封装。
class GomokuRoom {
  GomokuRoom(this.handle);
  final RoomHandle handle;

  /// 是否黑方 = 我的 deviceId 等于服务端 black_player_id（权威字段）。
  /// fallback 到 handle.latest 未到位时的 deviceId 前缀。
  bool get isBlack {
    final myId = handle.transport.deviceId;
    final s = handle.latest;
    if (s != null) {
      final blackId = s.context['black_player_id']?.toString();
      if (blackId != null) return myId == blackId;
    }
    return myId.startsWith('gm-black-');
  }

  /// 是否房主（黑方先手 = 房主）。
  bool get isHost => isBlack;

  String get deviceId => handle.transport.deviceId;

  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});
  Future<void> deal() => handle.applyAction(type: 'DEAL', params: const {});
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});
  Future<void> move(GomokuMove m) =>
      handle.applyAction(type: 'MOVE', params: {'move': m.toJson()});
  Future<void> resign() => handle.applyAction(type: 'RESIGN', params: const {});
  Future<void> declareWin(String winner) =>
      handle.applyAction(type: 'WIN', params: {'winner': winner});

  // ── Snapshot 便捷读取 ──

  /// 从 snapshot 取 black_player_id（权威服务端字段）。
  static String? blackPlayerId(Snapshot? s) {
    final raw = s?.context['black_player_id'];
    if (raw == null) return hostId(s);  // 兼容旧 snapshot
    return raw.toString();
  }

  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  static Map<String, String> players(Snapshot? s) {
    final raw = s?.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  static Map<String, bool> readyMap(Snapshot? s) {
    final raw = s?.context['ready'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v == true));
  }

  /// 终局胜方："black" / "white" / null。
  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  static Map<String, String> actionPermissions(Snapshot? s) {
    final raw = s?.context['action_permissions'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 从 snapshot history 重建落子序列。
  static List<GomokuMove> rebuildMoves(Snapshot? s) {
    if (s == null) return const [];
    final raw = s.context['history'];
    if (raw is! List) return const [];
    return raw
        .map((e) => GomokuMove.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 从落子序列重建棋盘状态（每格 0/1/2）。
  static GomokuBoard rebuildBoard(List<GomokuMove> moves) {
    final board = List<List<int>>.generate(
      kGomokuSize,
      (_) => List<int>.filled(kGomokuSize, 0),
    );
    for (final m in moves) {
      if (m.x >= 0 && m.x < kGomokuSize && m.y >= 0 && m.y < kGomokuSize) {
        board[m.y][m.x] = m.isBlack ? 1 : 2;
      }
    }
    return board;
  }

  /// 当前是否轮到黑方（history 空 → 黑先；否则与最后一步反色）。
  static bool isBlackTurn(List<GomokuMove> moves) {
    if (moves.isEmpty) return true;
    return !moves.last.isBlack;
  }

  /// 我能不能发这个 action？读服务端 action_permissions + 自己角色判定。
  static bool canPerform(
    String action,
    Snapshot? snap, {
    required bool isBlack,
    required bool isMyTurn,
  }) {
    final rule = actionPermissions(snap)[action];
    if (rule == null || rule == 'any') return true;
    if (rule == 'host') return isBlack;  // host = 黑方先手
    if (rule == 'current_player') return isMyTurn;
    return false;
  }

  // ── 连五判定 ──

  /// 判定 (x, y) 落子后是否形成连五（含 >5 的长连也算胜，简化规则）。
  /// 检查 4 个方向：横、竖、左斜、右斜。
  static bool hasFiveInRow(GomokuBoard board, int x, int y) {
    final v = board[y][x];
    if (v == 0) return false;
    const dirs = [
      [1, 0],   // 横
      [0, 1],   // 竖
      [1, 1],   // 右下斜
      [1, -1],  // 右上斜
    ];
    for (final d in dirs) {
      var count = 1;
      // 正方向延伸
      for (var i = 1; i < kGomokuWinLength; i++) {
        final nx = x + d[0] * i, ny = y + d[1] * i;
        if (nx < 0 || nx >= kGomokuSize || ny < 0 || ny >= kGomokuSize) break;
        if (board[ny][nx] != v) break;
        count++;
      }
      // 反方向延伸
      for (var i = 1; i < kGomokuWinLength; i++) {
        final nx = x - d[0] * i, ny = y - d[1] * i;
        if (nx < 0 || nx >= kGomokuSize || ny < 0 || ny >= kGomokuSize) break;
        if (board[ny][nx] != v) break;
        count++;
      }
      if (count >= kGomokuWinLength) return true;
    }
    return false;
  }

  /// 棋盘是否已满（平局判定，15x15 极少出现但保留）。
  static bool isBoardFull(List<GomokuMove> moves) =>
      moves.length >= kGomokuSize * kGomokuSize;
}
