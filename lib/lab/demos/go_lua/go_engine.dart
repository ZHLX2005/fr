// lib/lab/demos/go_lua/go_engine.dart
// 联机围棋 — 网络动作封装 + Snapshot 便捷读取 + 棋盘重建（含提子）+ 数子 + atari

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'go_constants.dart' show kGoSize;

export 'go_script.dart' show kGoScript;
export 'go_constants.dart' show kGoSize, kGoRelayUrl;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

/// 单步落子记录（与服务端 history 条目同构）。
class GoMove {
  const GoMove({
    required this.x,
    required this.y,
    required this.isBlack,
    this.captured = 0,
    this.isPass = false,
  });
  final int x;   // 0..8
  final int y;   // 0..8
  final bool isBlack;
  final int captured;  // 本步提子数
  final bool isPass;

  Map<String, dynamic> toJson() => isPass
      ? {'pass': true}
      : {'x': x, 'y': y, 'isBlack': isBlack, 'captured': captured};

  factory GoMove.fromJson(Map<String, dynamic> j) => GoMove(
        x: (j['x'] as num?)?.toInt() ?? 0,
        y: (j['y'] as num?)?.toInt() ?? 0,
        isBlack: j['isBlack'] == true,
        captured: (j['captured'] as num?)?.toInt() ?? 0,
        isPass: j['pass'] == true,
      );

  @override
  String toString() => isPass
      ? '过手'
      : '(${isBlack ? "黑" : "白"} $x,$y 提$captured)';
}

/// 棋盘状态：每格 0=空 / 1=黑 / 2=白。坐标 board[y][x]。
typedef GoBoard = List<List<int>>;

/// 联机围棋网络动作的语义封装。
class GoRoom {
  GoRoom(this.handle);
  final RoomHandle handle;

  /// 是否黑方 = 我的 deviceId 等于服务端 black_player_id（权威字段）。
  bool get isBlack {
    final myId = handle.transport.deviceId;
    final s = handle.latest;
    if (s != null) {
      final blackId = s.context['black_player_id']?.toString();
      if (blackId != null) return myId == blackId;
    }
    return myId.startsWith('go-black-');
  }

  /// 是否房主（host = 黑方先手）。
  bool get isHost => isBlack;

  String get deviceId => handle.transport.deviceId;

  Future<void> ack() => handle.applyAction(type: 'ACK', params: const {});
  Future<void> deal() => handle.applyAction(type: 'DEAL', params: const {});
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});
  Future<void> move(GoMove m) =>
      handle.applyAction(type: 'MOVE', params: {'move': m.toJson()});
  Future<void> pass() => handle.applyAction(type: 'PASS', params: const {});
  Future<void> resign() => handle.applyAction(type: 'RESIGN', params: const {});
  Future<void> declareWin({required int black, required int white}) =>
      handle.applyAction(type: 'WIN', params: {
        'area': {'black': black, 'white': white}
      });

  // ── Snapshot 便捷读取 ──

  static String? blackPlayerId(Snapshot? s) =>
      s?.context['black_player_id']?.toString();
  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  static Map<String, String> players(Snapshot? s) {
    final raw = s?.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 准备状态：{device_id: 是否已 ACK}（Task 5 lobby UI 依赖）。
  static Map<String, bool> readyMap(Snapshot? s) {
    final raw = s?.context['ready'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v == true));
  }

  static ({int black, int white}) captures(Snapshot? s) {
    final raw = s?.context['captures'];
    if (raw is! Map) return (black: 0, white: 0);
    return (
      black: (raw['black'] as num?)?.toInt() ?? 0,
      white: (raw['white'] as num?)?.toInt() ?? 0,
    );
  }

  static (int, int)? koSpot(Snapshot? s) {
    final raw = s?.context['ko_spot'];
    if (raw is! Map) return null;
    final x = (raw['x'] as num?)?.toInt();
    final y = (raw['y'] as num?)?.toInt();
    if (x == null || y == null) return null;
    return (x, y);
  }

  static int passes(Snapshot? s) => (s?.context['passes'] as num?)?.toInt() ?? 0;
  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  static Map<String, String> actionPermissions(Snapshot? s) {
    final raw = s?.context['action_permissions'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 从 snapshot history 重建落子序列。
  static List<GoMove> rebuildMoves(Snapshot? s) {
    if (s == null) return const [];
    final raw = s.context['history'];
    if (raw is! List) return const [];
    return raw
        .map((e) => GoMove.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 从落子序列在空棋盘上重放，得到完整棋局（含提子）。棋盘 board[y][x]。
  /// ⚠️ 必须用 applyMove 的返回值作为新盘继续 —— 否则被提的棋子不会消失！
  /// 每个非 pass 的 GoMove 都重放一次，提子由 applyMove 内部完成。
  static GoBoard rebuildBoard(List<GoMove> moves) {
    var board = List<List<int>>.generate(
      kGoSize,
      (_) => List<int>.filled(kGoSize, 0),
    );
    for (final m in moves) {
      if (m.isPass) continue;
      final nb = applyMove(board, m.x, m.y, m.isBlack ? 1 : 2);
      if (nb != null) board = nb;  // 关键：用提子后的新盘继续
    }
    return board;
  }

  /// 复刻服务端 handle_move 的核心：落子 + 提子。
  /// 返回提子后的新盘；自杀/占位返回 null。不修改入参 board。
  /// 这是客户端渲染/atari/数子的基础，与 Lua 同一算法。
  static GoBoard? applyMove(GoBoard board, int x, int y, int color) {
    final size = kGoSize;
    if (x < 0 || x >= size || y < 0 || y >= size) return null;
    if (board[y][x] != 0) return null;

    // 深拷贝
    final nb = List<List<int>>.generate(
      size, (r) => List<int>.from(board[r]));

    nb[y][x] = color;
    final opponent = color == 1 ? 2 : 1;
    final killed = <(int, int)>{};

    void collectDead(int sy, int sx, int c) {
      final dead = _deadGroup(nb, sy, sx, c);
      for (final p in dead) {
        killed.add(p);
      }
    }

    // 4 邻对方群
    const dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)];
    for (final (dy, dx) in dirs) {
      final ny = y + dy, nx = x + dx;
      if (ny < 0 || ny >= size || nx < 0 || nx >= size) continue;
      if (nb[ny][nx] == opponent) collectDead(ny, nx, opponent);
    }

    // 自杀判定：killed 空且自己无气
    final suicide = _deadGroup(nb, y, x, color);
    if (killed.isEmpty && suicide.isNotEmpty) return null;

    for (final (ky, kx) in killed) {
      nb[ky][kx] = 0;
    }
    return nb;
  }

  /// 泛洪找无气群（翻译自 orca0613）。有气返回空集合。
  static Set<(int, int)> _deadGroup(GoBoard board, int sy, int sx, int color) {
    final size = kGoSize;
    if (sy < 0 || sy >= size || sx < 0 || sx >= size) return {};
    if (board[sy][sx] != color) return {};

    final opponent = color == 1 ? 2 : 1;
    final nb = List<List<int>>.generate(size, (r) => List<int>.from(board[r]));
    final dead = <(int, int)>{};
    final stack = <(int, int)>[(sy, sx)];
    const dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)];
    while (stack.isNotEmpty) {
      final (cy, cx) = stack.removeLast();
      if (cy < 0 || cy >= size || cx < 0 || cx >= size) continue;
      if (nb[cy][cx] == color) {
        nb[cy][cx] = opponent;  // 标记已访问
        dead.add((cy, cx));
        for (final (dy, dx) in dirs) {
          stack.add((cy + dy, cx + dx));
        }
      } else if (nb[cy][cx] == opponent) {
        // 已访问或对方
      } else {
        return {};  // 遇到空点 → 有气，不死
      }
    }
    return dead;
  }

  /// 当前是否轮到黑方。**与服务端 Lua 完全一致：pass 占槽位**，
  /// `(moves.length % 2) == 0` 为黑回合（空 → 黑先）。不要跳过 pass！
  /// 这是联机正确性的关键 —— 若跳过 pass 会与服务端 current_player 推导
  /// （`#history % 2` 偶黑奇白）冲突，pass 后客户端按钮错乱 + 服务端拒 MOVE → 死锁。
  static bool isBlackTurn(List<GoMove> moves) {
    return moves.length % 2 == 0;
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
    if (rule == 'host') return isBlack;
    if (rule == 'current_player') return isMyTurn;
    return false;
  }

  // ── 数子（中国规则 area：子 + 空，不判死/不贴目）──

  /// 从棋盘计算黑/白点数：子 + 被单色包围的空点（简单 flood fill）。
  /// 空点邻接双方 → 视为无主，不计任何一方。
  static ({int black, int white}) detectArea(GoBoard board) {
    final size = kGoSize;
    var black = 0, white = 0;
    // 先数子
    for (final row in board) {
      for (final v in row) {
        if (v == 1) {
          black++;
        } else if (v == 2) {
          white++;
        }
      }
    }
    // 数空点归属（flood fill）
    final visited = List<List<bool>>.generate(
      size, (_) => List<bool>.filled(size, false));
    const dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)];
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (board[y][x] != 0 || visited[y][x]) continue;
        // BFS 一个空区
        final region = <(int, int)>[(y, x)];
        visited[y][x] = true;
        final borders = <int>{};
        var head = 0;
        while (head < region.length) {
          final (cy, cx) = region[head++];
          for (final (dy, dx) in dirs) {
            final ny = cy + dy, nx = cx + dx;
            if (ny < 0 || ny >= size || nx < 0 || nx >= size) continue;
            final v = board[ny][nx];
            if (v != 0) {
              borders.add(v);
            } else if (!visited[ny][nx]) {
              visited[ny][nx] = true;
              region.add((ny, nx));
            }
          }
        }
        // 只被单色包围 → 归该色
        if (borders.length == 1) {
          if (borders.contains(1)) {
            black += region.length;
          } else if (borders.contains(2)) {
            white += region.length;
          }
        }
      }
    }
    return (black: black, white: white);
  }

  // ── atari（打吃）提示 ──

  /// 某位置所在棋群的气（相邻空点集合）。空点返回空。
  static Set<(int, int)> libertiesAt(GoBoard board, int x, int y) {
    final size = kGoSize;
    if (x < 0 || x >= size || y < 0 || y >= size) return {};
    if (board[y][x] == 0) return {};
    // BFS 同色群
    final color = board[y][x];
    final chain = <(int, int)>[(y, x)];
    final visited = <(int, int)>{(y, x)};
    final liberties = <(int, int)>{};
    const dirs = [(0, -1), (0, 1), (-1, 0), (1, 0)];
    var head = 0;
    while (head < chain.length) {
      final (cy, cx) = chain[head++];
      for (final (dy, dx) in dirs) {
        final ny = cy + dy, nx = cx + dx;
        if (ny < 0 || ny >= size || nx < 0 || nx >= size) continue;
        final v = board[ny][nx];
        if (v == 0) {
          liberties.add((ny, nx));
        } else if (v == color && !visited.contains((ny, nx))) {
          visited.add((ny, nx));
          chain.add((ny, nx));
        }
      }
    }
    return liberties;
  }

  /// 某位置所在棋群是否在打吃（气==1）。空点返回 false。
  static bool isAtari(GoBoard board, int x, int y) {
    if (x < 0 || x >= kGoSize || y < 0 || y >= kGoSize) return false;
    if (board[y][x] == 0) return false;
    return libertiesAt(board, x, y).length == 1;
  }

  /// 所有处于打吃状态的某色棋子坐标集合（用于高亮）。
  static Set<(int, int)> groupsInAtari(GoBoard board, int color) {
    final size = kGoSize;
    final result = <(int, int)>{};
    final visited = <(int, int)>{};
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (board[y][x] != color) continue;
        if (visited.contains((y, x))) continue;
        // BFS 群
        final chain = <(int, int)>[(y, x)];
        final chainSet = <(int, int)>{(y, x)};
        var head = 0;
        while (head < chain.length) {
          final (cy, cx) = chain[head++];
          for (final (dy, dx) in const [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
            final ny = cy + dy, nx = cx + dx;
            if (ny < 0 || ny >= size || nx < 0 || nx >= size) continue;
            if (board[ny][nx] == color && !chainSet.contains((ny, nx))) {
              chainSet.add((ny, nx));
              chain.add((ny, nx));
            }
          }
        }
        visited.addAll(chainSet);
        if (libertiesAt(board, x, y).length == 1) {
          result.addAll(chainSet);
        }
      }
    }
    return result;
  }
}
