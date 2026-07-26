// lib/lab/demos/tetris_lua/engine.dart
//
// 俄罗斯方块 — 本地游戏引擎 + 网络动作封装。
//
// 两个核心类：
//   [TetrisEngine]   纯本地逻辑：网格/方块/旋转/消行/计分/game over。
//                    与网络无关，操作即时零延迟。落定时方法返回 true，
//                    由 UI 层决定是否 SYNC。
//   [TetrisRoom]     网络动作封装 + Snapshot 读取（共享序列/双方状态/胜负）。

import 'package:flutter/foundation.dart';

import 'constants.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

export 'tetris_script.dart' show kTetrisScript;
export 'constants.dart';
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

// ══════════════════════════════════════════════════════════════
// 方块
// ══════════════════════════════════════════════════════════════

/// 一个下落中的方块：类型 + 当前旋转矩阵 + 左上角坐标 (x=列, y=行)。
class TetrisPiece {
  TetrisPiece(this.type, this.matrix, this.x, this.y);
  final int type; // 1..7
  List<List<int>> matrix; // 可变：旋转时整体替换
  int x, y;
}

// ══════════════════════════════════════════════════════════════
// 本地引擎
// ══════════════════════════════════════════════════════════════

class TetrisEngine extends ChangeNotifier {
  TetrisEngine(List<int> sequence) : _sequence = sequence {
    reset();
  }

  List<int> _sequence;
  late List<List<int>> grid; // [row][col]，0=空 / 1..7=方块类型
  TetrisPiece? current;
  int? holdType;
  bool _holdLocked = false; // 同一块只能 hold 一次
  int pieceIndex = 0;
  int score = 0;
  int lines = 0;
  int level = 0;
  bool alive = true;

  List<int> get sequence => _sequence;

  /// 下一个将出的方块类型（Next 预览，不消费 index）。
  int? get nextType =>
      pieceIndex < _sequence.length ? _sequence[pieceIndex] : null;

  void reset() {
    grid = List.generate(
      kTetrisRows,
      (_) => List.filled(kTetrisCols, kEmptyCell),
    );
    pieceIndex = 0;
    score = 0;
    lines = 0;
    level = 0;
    alive = true;
    holdType = null;
    _holdLocked = false;
    _spawn();
  }

  /// RESET 后服务端重生成序列；客户端换上新序列重玩。
  void replaceSequence(List<int> seq) {
    _sequence = seq;
    reset();
  }

  int _consumeNext() {
    if (pieceIndex >= _sequence.length) return kPieceI; // 超长局兜底
    return _sequence[pieceIndex++];
  }

  void _spawn() {
    final type = _consumeNext();
    final m = _cloneMatrix(type);
    final x = (kTetrisCols - m.first.length) ~/ 2;
    final piece = TetrisPiece(type, m, x, 0);
    if (_collides(piece.matrix, piece.x, piece.y)) {
      // 出生即碰撞 = 堆顶，game over
      alive = false;
      current = null;
    } else {
      current = piece;
      _holdLocked = false;
    }
    notifyListeners();
  }

  static List<List<int>> _cloneMatrix(int type) =>
      kPieceMatrices[type]!.map((r) => List<int>.from(r)).toList();

  /// 矩阵顺时针 90°：r[j][n-1-i] = m[i][j]
  static List<List<int>> _rotateCW(List<List<int>> m) {
    final n = m.length;
    final r = List.generate(n, (_) => List.filled(n, 0));
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        r[j][n - 1 - i] = m[i][j];
      }
    }
    return r;
  }

  /// 矩阵逆时针 90°：r[n-1-j][i] = m[i][j]
  static List<List<int>> _rotateCCW(List<List<int>> m) {
    final n = m.length;
    final r = List.generate(n, (_) => List.filled(n, 0));
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        r[n - 1 - j][i] = m[i][j];
      }
    }
    return r;
  }

  bool _collides(List<List<int>> m, int px, int py) {
    for (var i = 0; i < m.length; i++) {
      for (var j = 0; j < m[i].length; j++) {
        if (m[i][j] == 0) continue;
        final gx = px + j, gy = py + i;
        if (gx < 0 || gx >= kTetrisCols || gy >= kTetrisRows) return true;
        if (gy < 0) continue; // 顶部出生区允许暂越界
        if (grid[gy][gx] != kEmptyCell) return true;
      }
    }
    return false;
  }

  // ── 操作（即时，不走网络）──

  bool moveX(int dx) {
    final c = current;
    if (c == null || !alive) return false;
    if (_collides(c.matrix, c.x + dx, c.y)) return false;
    c.x += dx;
    notifyListeners();
    return true;
  }

  void rotateCW() => _rotate(_rotateCW);
  void rotateCCW() => _rotate(_rotateCCW);

  void _rotate(List<List<int>> Function(List<List<int>>) rotateFn) {
    final c = current;
    if (c == null || !alive || c.type == kPieceO) return;
    final rotated = rotateFn(c.matrix);
    // 简化踢墙：依次尝试 0/-1/+1/-2/+2 横向偏移
    for (final dx in const [0, -1, 1, -2, 2]) {
      if (!_collides(rotated, c.x + dx, c.y)) {
        c.x += dx;
        c.matrix = rotated;
        notifyListeners();
        return;
      }
    }
  }

  /// 下移一格（重力 tick 或软降）。
  /// 返回 true = 落定（外部据此发 SYNC）；false = 仍在下落。
  bool stepDown({int scorePerCell = 0}) {
    final c = current;
    if (c == null || !alive) return false;
    if (!_collides(c.matrix, c.x, c.y + 1)) {
      c.y += 1;
      if (scorePerCell > 0) score += scorePerCell;
      notifyListeners();
      return false;
    }
    _lock();
    return true;
  }

  /// 硬降：直降到底 + 加分 + 落定。返回 true（落定）供 UI 触发 SYNC。
  bool hardDrop() {
    final c = current;
    if (c == null || !alive) return false;
    var dropped = 0;
    while (!_collides(c.matrix, c.x, c.y + 1)) {
      c.y += 1;
      dropped++;
    }
    score += dropped * kHardDropScore;
    _lock();
    return true;
  }

  /// 暂存当前块 / 与暂存槽交换。同一块只能用一次。
  void hold() {
    final c = current;
    if (c == null || !alive || _holdLocked) return;
    final curType = c.type;
    if (holdType == null) {
      holdType = curType;
      _spawn(); // 出新块（序列推进）
    } else {
      final swap = holdType!;
      holdType = curType;
      final m = _cloneMatrix(swap);
      final x = (kTetrisCols - m.first.length) ~/ 2;
      final np = TetrisPiece(swap, m, x, 0);
      if (_collides(np.matrix, np.x, np.y)) {
        alive = false;
        current = null;
      } else {
        current = np;
      }
    }
    _holdLocked = true;
    notifyListeners();
  }

  void _lock() {
    final c = current!;
    for (var i = 0; i < c.matrix.length; i++) {
      for (var j = 0; j < c.matrix[i].length; j++) {
        if (c.matrix[i][j] == 0) continue;
        final gx = c.x + j, gy = c.y + i;
        if (gy >= 0 && gy < kTetrisRows && gx >= 0 && gx < kTetrisCols) {
          grid[gy][gx] = c.type;
        }
      }
    }
    _clearLines();
    _spawn();
  }

  void _clearLines() {
    var cleared = 0;
    for (var y = kTetrisRows - 1; y >= 0; y--) {
      if (grid[y].every((cell) => cell != kEmptyCell)) {
        grid.removeAt(y);
        grid.insert(0, List.filled(kTetrisCols, kEmptyCell));
        cleared++;
        y++; // 下移后重新检查该行
      }
    }
    if (cleared > 0) {
      lines += cleared;
      score += kLineScores[cleared] * (level + 1);
      level = lines ~/ kLinesPerLevel;
    }
  }

  /// ghost（落点预览）相对当前块的 y 偏移。
  int ghostOffset() {
    final c = current;
    if (c == null) return 0;
    var dy = 0;
    while (!_collides(c.matrix, c.x, c.y + dy + 1)) {
      dy++;
    }
    return dy;
  }

  /// 用于 SYNC 上报的堆积快照（深拷贝，避免与 grid 共享引用）。
  List<List<int>> boardSnapshot() =>
      grid.map((r) => List<int>.from(r)).toList();
}

// ══════════════════════════════════════════════════════════════
// 网络封装 + Snapshot 读取
// ══════════════════════════════════════════════════════════════

/// 单个玩家的实时状态（从 snapshot.states[did] 解析）。
class TetrisPlayerState {
  const TetrisPlayerState({
    required this.board,
    required this.score,
    required this.lines,
    required this.pieceIndex,
    required this.alive,
  });

  final List<List<int>> board;
  final int score;
  final int lines;
  final int pieceIndex;
  final bool alive;
}

class TetrisRoom {
  TetrisRoom(this.handle);
  final RoomHandle handle;

  String get deviceId => handle.transport.deviceId;
  bool get isHost => deviceId == hostId(handle.latest);

  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});
  Future<void> start() => handle.applyAction(type: 'START', params: const {});
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});

  /// 自己堆顶 game over，上报最终分。服务端第一个 BUST 扣 bust_penalty，
  /// 双方都 BUST 后比 final_score 定胜。
  Future<void> bust(int score) =>
      handle.applyAction(type: 'BUST', params: {'score': score});

  Future<void> syncState({
    required List<List<int>> board,
    required int score,
    required int lines,
    required int pieceIndex,
    required bool alive,
  }) => handle.applyAction(
    type: 'SYNC',
    params: {
      'state': {
        'board': board,
        'score': score,
        'lines': lines,
        'pieceIndex': pieceIndex,
        'alive': alive,
      },
    },
  );

  // ── Snapshot 读取（静态，便于 UI 无实例调用）──

  /// 共享方块序列。snapshot 必带（on_init 生成）。
  static List<int> sequence(Snapshot? s) {
    final raw = s?.context['piece_sequence'];
    if (raw is! List) return const [];
    return raw.map((e) => (e as num).toInt()).toList();
  }

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

  /// 某玩家的实时状态。未 SYNC 过返回 null。
  static TetrisPlayerState? stateOf(Snapshot? s, String deviceId) {
    final states = s?.context['states'];
    if (states is! Map) return null;
    final raw = states[deviceId];
    if (raw is! Map) return null;
    final boardRaw = raw['board'];
    List<List<int>> board = const [];
    if (boardRaw is List) {
      board = boardRaw.map((row) {
        if (row is! List) return const <int>[];
        return row.map((c) => (c as num?)?.toInt() ?? 0).toList();
      }).toList();
    }
    return TetrisPlayerState(
      board: board,
      score: (raw['score'] as num?)?.toInt() ?? 0,
      lines: (raw['lines'] as num?)?.toInt() ?? 0,
      pieceIndex: (raw['pieceIndex'] as num?)?.toInt() ?? 0,
      alive: raw['alive'] != false,
    );
  }

  /// 终局赢家 device_id（final_score 高的那一方）。
  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  /// 首个 BUST（先堆顶）的那一方，用于"先 GG"语义展示。
  static String? loserId(Snapshot? s) => s?.context['loser_id']?.toString();

  /// 某玩家 BUST 后的最终分（score=扣分后、raw=原始、penalty=扣分）。
  /// 未 BUST 返回 null。
  static TetrisFinalScore? finishedOf(Snapshot? s, String deviceId) {
    final fin = s?.context['finished'];
    if (fin is! Map) return null;
    final raw = fin[deviceId];
    if (raw is! Map) return null;
    return TetrisFinalScore(
      score: (raw['score'] as num?)?.toInt() ?? 0,
      rawScore: (raw['raw'] as num?)?.toInt() ?? 0,
      penalty: (raw['penalty'] as num?)?.toInt() ?? 0,
    );
  }

  /// 对手 device_id（players 里除自己外的一个）。
  static String? opponentId(Snapshot? s, String myId) {
    final p = players(s);
    for (final k in p.keys) {
      if (k != myId) return k;
    }
    return null;
  }
}

/// BUST 后的最终分明细。
class TetrisFinalScore {
  const TetrisFinalScore({
    required this.score,
    required this.rawScore,
    required this.penalty,
  });
  final int score; // 扣分后（用于比胜）
  final int rawScore; // 客户端上报的原始分
  final int penalty; // 先 BUST 扣的分（第一个为 bust_penalty，其余 0）
}
