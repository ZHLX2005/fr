// lib/lab/demos/jungle_chess_lua/jungle_engine.dart
//
// 斗兽棋 Lua 版 — 网络动作封装 + Snapshot 便捷读取 + 胜负判定 + 历史重建。
//
// 设计要点：
//   - 服务端只存 history（落子序列），棋盘从权威 history 重建
//   - 客户端用本地 JungleEngine 验证走法 + 重建 GameState（保证双方严格一致）
//   - 角色判定：服务端权威字段 top_player_id → 客户端派生 _imTop
//   - 镜像：host 端（top）整体 Transform.flip(flipY: true) 翻转棋盘
//   - 胜负由客户端算完后发 WIN（服务端仅校验角色）

import 'package:xiaodouzi_fr/core/jungle_chess/constants/jungle_constants.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/engine/jungle_engine.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/game_state.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/move.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/piece.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

export 'jungle_lua_script.dart' show kJungleChessScript;
export 'jungle_constants.dart' show kJungleLuaRelayUrl;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

// ══════════════════════════════════════════════════════════════
// 走法记录（与 Lua 服务端 history 条目同构）
// ══════════════════════════════════════════════════════════════

/// 一条走法（服务端权威）。canonical row/col：红方(top)在 row 0 一侧。
///
/// 棋子用 "color" 标识归属方（"red"=top, "blue"=bottom），不存 animal。
/// 重建时从上一局面 / 起点 from 推回 animal。
class JungleMoveRecord {
  final int fromRow;
  final int fromCol;
  final int toRow;
  final int toCol;
  final String color; // "red" | "blue"
  final bool isRiverJump;
  final int? capturedAnimal; // 被吃子的 animal index（可选，简化重建）
  final int round;

  const JungleMoveRecord({
    required this.fromRow,
    required this.fromCol,
    required this.toRow,
    required this.toCol,
    required this.color,
    this.isRiverJump = false,
    this.capturedAnimal,
    required this.round,
  });

  Map<String, dynamic> toJson() => {
        'from': {'row': fromRow, 'col': fromCol},
        'to': {'row': toRow, 'col': toCol},
        'color': color,
        'isRiverJump': isRiverJump,
        'capturedAnimal': capturedAnimal,
        'round': round,
      };

  factory JungleMoveRecord.fromJson(Map<String, dynamic> j) {
    final from = j['from'] as Map;
    final to = j['to'] as Map;
    return JungleMoveRecord(
      fromRow: (from['row'] as num).toInt(),
      fromCol: (from['col'] as num).toInt(),
      toRow: (to['row'] as num).toInt(),
      toCol: (to['col'] as num).toInt(),
      color: j['color'] as String,
      isRiverJump: j['isRiverJump'] == true,
      capturedAnimal: j['capturedAnimal'] is num
          ? (j['capturedAnimal'] as num).toInt()
          : null,
      round: (j['round'] as num).toInt(),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 网络动作的语义封装
// ══════════════════════════════════════════════════════════════

/// 斗兽棋互联网对战的网络动作封装（语义层）。
class JungleRoom {
  JungleRoom(this.handle);
  final RoomHandle handle;

  /// 我是 top（host）吗？用服务端权威字段 top_player_id 判定。
  bool get isTop {
    final myId = handle.transport.deviceId;
    final s = handle.latest;
    if (s != null) {
      final topId = s.context['top_player_id']?.toString();
      if (topId != null) return myId == topId;
    }
    return false;
  }

  /// 我是红方（top）还是蓝方（bottom）。
  PlayerColor get myColor => isTop ? PlayerColor.red : PlayerColor.blue;

  /// 是否房主（= top = 红方）。
  bool get isHost => isTop;

  String get deviceId => handle.transport.deviceId;

  // ── 网络动作 ──

  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});
  Future<void> deal() => handle.applyAction(type: 'DEAL', params: const {});
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});
  Future<void> resign() =>
      handle.applyAction(type: 'RESIGN', params: const {});
  Future<void> declareWin(String winner) =>
      handle.applyAction(type: 'WIN', params: {'winner': winner});
  Future<void> move(JungleMoveRecord m) =>
      handle.applyAction(type: 'MOVE', params: {'move': m.toJson()});

  // ── Snapshot 便捷读取 ──

  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();
  static String? topPlayerId(Snapshot? s) =>
      s?.context['top_player_id']?.toString() ?? hostId(s);

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

  /// 终局胜方："blue" | "red" | null。
  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  static Map<String, String> actionPermissions(Snapshot? s) {
    final raw = s?.context['action_permissions'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 从 snapshot history 重建走法序列。
  static List<JungleMoveRecord> rebuildHistory(Snapshot? s) {
    if (s == null) return const [];
    final raw = s.context['history'];
    if (raw is! List) return const [];
    return raw
        .map((e) =>
            JungleMoveRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ── 棋盘重建（从权威 history 用 JungleEngine 一步步重放）──

  /// 用初始局面 + history 重建 GameState（双方严格一致）。
  static GameState rebuildBoard(List<JungleMoveRecord> history) {
    var s = JungleEngine.createInitialState();
    for (final m in history) {
      final from = (row: m.fromRow, col: m.fromCol);
      final to = (row: m.toRow, col: m.toCol);
      final next = JungleEngine.movePiece(s, from, to);
      if (next != null) s = next;
    }
    return s;
  }

  /// 当前轮到谁走（top=red, bottom=blue）。空 history → red（top）先手。
  static PlayerColor currentTurnPlayer(List<JungleMoveRecord> history) {
    if (history.isEmpty) return PlayerColor.red;
    final lastColor = history.last.color == 'red'
        ? PlayerColor.red
        : PlayerColor.blue;
    return lastColor == PlayerColor.red
        ? PlayerColor.blue
        : PlayerColor.red;
  }

  /// 我能不能发这个 action？读服务端 action_permissions + 自己角色判定。
  static bool canPerform(
    String action,
    Snapshot? snap, {
    required bool isTop,
    required bool isMyTurn,
  }) {
    final rule = actionPermissions(snap)[action];
    if (rule == null || rule == 'any') return true;
    if (rule == 'host') return isTop;
    if (rule == 'current_player') return isMyTurn;
    if (rule == 'non_current_player') {
      // WIN 用：刚下完最后一步的人
      final history = rebuildHistory(snap);
      if (history.isEmpty) return false;
      final lastColor = history.last.color == 'red'
          ? PlayerColor.red
          : PlayerColor.blue;
      final lastIsTop = lastColor == PlayerColor.red;
      return lastIsTop == isTop;
    }
    return false;
  }

  // ── 胜负判定（客户端算，发 WIN）──

  /// 判定当前 GameState 是否终局；返回 winner（"blue"|"red"|null）+ reason。
  static ({String? winner, String reason}) checkWinner(GameState s) {
    final r = JungleEngine.checkGameEnd(s);
    if (!r.isOver) return (winner: null, reason: '');
    final w = r.winner;
    if (w == null) return (winner: null, reason: r.reason ?? '平局');
    return (
      winner: w == PlayerColor.red ? 'red' : 'blue',
      reason: r.reason ?? '',
    );
  }

  /// 把 GameState 转成服务端 winner 字符串（用于发 WIN）。
  static String? winnerOfState(GameState s) {
    final w = s.winner;
    if (w == null) return null;
    return w == PlayerColor.red ? 'red' : 'blue';
  }

  /// GameState 转为 Move（仅取所需字段，供 MOVE 上报）。
  static JungleMoveRecord moveToRecord(Move m, String color) {
    return JungleMoveRecord(
      fromRow: m.from.row,
      fromCol: m.from.col,
      toRow: m.to.row,
      toCol: m.to.col,
      color: color,
      isRiverJump: m.isRiverJump,
      round: m.roundNumber,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 棋盘字母表示（大小写区分双方）—— 棋谱记录 / 调试 / 教程
//
// 约定（中文象棋 / 国际惯例）：
//   大写 = 红方 (top)
//   小写 = 蓝方 (bottom)
//
// 棋子字母（animal 首字母）：
//   r=rat  c=cat  d=dog  w=wolf  p=leopard  t=tiger  l=lion  e=elephant
//
// 例子：
//   "R" 红方鼠, "r" 蓝方鼠
//   "E" 红方象, "e" 蓝方象
// ══════════════════════════════════════════════════════════════

/// animal → 字母（统一用小写，调用方按 color 决定大小写）
const Map<Animal, String> kAnimalLetter = {
  Animal.rat: 'r',
  Animal.cat: 'c',
  Animal.dog: 'd',
  Animal.wolf: 'w',
  Animal.leopard: 'p',
  Animal.tiger: 't',
  Animal.lion: 'l',
  Animal.elephant: 'e',
};

/// 反向：字母 → animal（大小写都接受）
Animal? animalFromLetter(String letter) {
  final l = letter.toLowerCase();
  for (final e in kAnimalLetter.entries) {
    if (e.value == l) return e.key;
  }
  return null;
}

/// 棋子 → 棋谱字母（红方大写 / 蓝方小写）
String pieceLetter(Piece piece) {
  final l = kAnimalLetter[piece.animal]!;
  return piece.color == PlayerColor.red ? l.toUpperCase() : l;
}

/// 棋谱字母 → 棋子（需要 color 决定大小写归属）。
Piece? pieceFromLetter(String letter, PlayerColor color, Coord pos) {
  final animal = animalFromLetter(letter);
  if (animal == null) return null;
  return Piece(animal: animal, color: color, position: pos);
}

/// 棋盘 → 9x7 字母串数组（debug / 教程 / 棋谱回放）。
List<String> boardToLetterRows(GameState s) {
  final rows = <String>[];
  for (int r = 0; r < kBoardRows; r++) {
    final buf = StringBuffer();
    for (int c = 0; c < kBoardCols; c++) {
      final idx = r * kBoardCols + c;
      final p = s.pieces[idx];
      if (p == null || !p.isAlive) {
        buf.write('.');
      } else {
        buf.write(pieceLetter(p));
      }
    }
    rows.add(buf.toString());
  }
  return rows;
}
