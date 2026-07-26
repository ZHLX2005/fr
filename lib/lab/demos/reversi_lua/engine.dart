// lib/lab/demos/reversi_lua/engine.dart
// 黑白翻转棋 Lua 版 — 网络动作封装 + Snapshot 便捷读取 + 终局判定

import 'package:xiaodouzi_fr/core/reversi/models/reversi_board.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

import 'constants.dart' show kReversiSize;

export 'reversi_script.dart' show kReversiScript;
export 'constants.dart' show kReversiSize;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

/// 单步落子记录（与服务端 history 条目同构）。
class ReversiMove {
  const ReversiMove({required this.x, required this.y, required this.isBlack});
  final int x;
  final int y;
  final bool isBlack;

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'isBlack': isBlack};

  factory ReversiMove.fromJson(Map<String, dynamic> j) => ReversiMove(
        x: (j['x'] as num).toInt(),
        y: (j['y'] as num).toInt(),
        isBlack: j['isBlack'] == true,
      );

  Position toPosition() => Position(y, x); // row = y, col = x

  @override
  String toString() => '(${isBlack ? "黑" : "白"} $x,$y)';
}

/// 黑白翻转棋网络动作的语义封装。
class ReversiRoom {
  ReversiRoom(this.handle);
  final RoomHandle handle;

  /// 是否黑方 = 我的 deviceId 等于服务端 black_player_id（权威字段）。
  bool get isBlack {
    final myId = handle.transport.deviceId;
    final s = handle.latest;
    if (s != null) {
      final blackId = s.context['black_player_id']?.toString();
      if (blackId != null) return myId == blackId;
    }
    return false; // snapshot 未到位时不要默认（避免与 reset 后随机分配错位）
  }

  /// 是否房主（black_player_id 可能 ≠ host）。
  bool get isHost {
    final s = handle.latest;
    if (s != null) {
      final hostId = s.context['host_id']?.toString();
      if (hostId != null) return handle.transport.deviceId == hostId;
    }
    return false;
  }

  String get deviceId => handle.transport.deviceId;

  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});
  Future<void> deal() => handle.applyAction(type: 'DEAL', params: const {});
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});
  Future<void> move(ReversiMove m) =>
      handle.applyAction(type: 'MOVE', params: {'move': m.toJson()});
  Future<void> undo() => handle.applyAction(type: 'UNDO', params: const {});
  Future<void> resign() =>
      handle.applyAction(type: 'RESIGN', params: const {});
  Future<void> declareWin(String winner) =>
      handle.applyAction(type: 'WIN', params: {'winner': winner});

  // ── Snapshot 便捷读取 ──

  static String? blackPlayerId(Snapshot? s) {
    final raw = s?.context['black_player_id'];
    return raw?.toString();
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

  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  static Map<String, String> actionPermissions(Snapshot? s) {
    final raw = s?.context['action_permissions'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 从 snapshot history 重建落子序列。
  static List<ReversiMove> rebuildMoves(Snapshot? s) {
    if (s == null) return const [];
    final raw = s.context['history'];
    if (raw is! List) return const [];
    return raw
        .map((e) => ReversiMove.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 从落子序列在空棋盘上重放，得到完整棋局（含 8x8 初始 4 子）。
  /// 返回 PieceType 二维矩阵 cells[row][col]。
  static List<List<PieceType>> rebuildBoard(List<ReversiMove> moves) {
    var board = ReversiBoard.initial(size: kReversiSize);
    for (final m in moves) {
      final pos = m.toPosition();
      // 合法性校验（如果服务端存了非法步，回放会原样跳过）
      if (!board.isLegalMove(pos, m.isBlack ? PieceType.black : PieceType.white)) {
        continue;
      }
      board = board.placeStone(pos, m.isBlack ? PieceType.black : PieceType.white);
    }
    return List.generate(
      kReversiSize,
      (r) => List.generate(kReversiSize, (c) => board.cellAt(r, c)),
    );
  }

  /// 当前是否轮到黑方（history 空 → 黑先；否则与最后一步反色）。
  static bool isBlackTurn(List<ReversiMove> moves) {
    if (moves.isEmpty) return true;
    return !moves.last.isBlack;
  }

  /// 我能不能发这个 action？读服务端 action_permissions + 自己角色判定。
  static bool canPerform(
    String action,
    Snapshot? snap, {
    required bool isBlack,
    required bool isMyTurn,
    required bool isHost,
  }) {
    final rule = actionPermissions(snap)[action];
    if (rule == null || rule == 'any') return true;
    if (rule == 'host') return isHost;
    if (rule == 'current_player') return isMyTurn;
    if (rule == 'non_current_player') return !isMyTurn;
    return false;
  }

  // ── 终局判定 ──

  /// 终局胜方。
  ///
  /// 判定规则：
  /// - 棋盘满 → 子数多者胜 / 平局
  /// - 双方均无合法步 → 同上
  /// - 否则继续，返回 null
  static String? detectWinner(
    List<List<PieceType>> cells, {
    required bool blackCanMove,
    required bool whiteCanMove,
  }) {
    int black = 0, white = 0, empty = 0;
    for (final row in cells) {
      for (final c in row) {
        if (c == PieceType.black) {
          black++;
        } else if (c == PieceType.white) {
          white++;
        } else {
          empty++;
        }
      }
    }

    final boardFull = empty == 0;
    final bothNoMove = !blackCanMove && !whiteCanMove;
    if (!boardFull && !bothNoMove) return null;

    if (black > white) return 'black';
    if (white > black) return 'white';
    return 'draw';
  }

  /// 当前方所有合法落子位置（用于提示点 + 校验）。
  static List<Position> legalMovesFor(
    List<List<PieceType>> cells,
    bool isBlack,
  ) {
    final board = ReversiBoard.fromCells(cells);
    return board.legalMovesFor(isBlack ? PieceType.black : PieceType.white);
  }
}