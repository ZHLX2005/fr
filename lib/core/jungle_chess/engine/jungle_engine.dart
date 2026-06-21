// lib/core/jungle_chess/engine/jungle_engine.dart
import '../constants/jungle_constants.dart';
import '../models/piece.dart';
import '../models/move.dart';
import '../models/game_state.dart';

/// 斗兽棋纯函数规则引擎
///
/// 所有方法均为 `static` 纯函数，不依赖 Flutter / 网络 / 时间。
/// 输入 GameState，输出新的 GameState 或判定结果。
///
/// 设计参考：Layheng-Hok/Jungle-Chess（Java）规则引擎文档
/// 严格按其判定逻辑移植（functional 风格，不依赖外部状态）。
abstract final class JungleEngine {
  // ============================================================
  // 初始布局
  // ============================================================

  /// 创建标准开局（16 子对称布局）
  ///
  /// 蓝方（底部）：
  ///   Row 8: 虎 - 陷 - 陷 穴 陷 - 狮
  ///   Row 7: - 猫 - 陷 - 狗 -
  ///   Row 6: 象 - 狼 - 豹 - 鼠
  /// 红方（顶部，row 0-2）：
  ///   Row 0: 狮 - 陷 - 穴 陷 - 虎
  ///   Row 1: - 狗 - 陷 - 猫 -
  ///   Row 2: 鼠 - 豹 - 狼 - 象
  static GameState createInitialState() {
    final pieces = <int, Piece>{};

    void place(int row, int col, Animal animal, PlayerColor color) {
      final i = coordIndex(row, col);
      pieces[i] = Piece(
        animal: animal,
        color: color,
        position: (row: row, col: col),
      );
    }

    // 蓝方 (下方)
    place(8, 0, Animal.tiger, PlayerColor.blue);
    place(8, 6, Animal.lion, PlayerColor.blue);
    place(7, 1, Animal.cat, PlayerColor.blue);
    place(7, 5, Animal.dog, PlayerColor.blue);
    place(6, 0, Animal.elephant, PlayerColor.blue);
    place(6, 2, Animal.wolf, PlayerColor.blue);
    place(6, 4, Animal.leopard, PlayerColor.blue);
    place(6, 6, Animal.rat, PlayerColor.blue);

    // 红方 (上方)
    place(0, 0, Animal.lion, PlayerColor.red);
    place(0, 6, Animal.tiger, PlayerColor.red);
    place(1, 1, Animal.dog, PlayerColor.red);
    place(1, 5, Animal.cat, PlayerColor.red);
    place(2, 0, Animal.rat, PlayerColor.red);
    place(2, 2, Animal.leopard, PlayerColor.red);
    place(2, 4, Animal.wolf, PlayerColor.red);
    place(2, 6, Animal.elephant, PlayerColor.red);

    return GameState(pieces: pieces, currentTurn: PlayerColor.blue);
  }

  // ============================================================
  // 合法走法
  // ============================================================

  /// 获取 [pos] 处棋子的所有合法目标坐标
  static List<Coord> getValidMoves(GameState state, Coord pos) {
    final idx = pos.index;
    final piece = state.pieces[idx];
    if (piece == null || !piece.isAlive) return <Coord>[];
    if (piece.color != state.currentTurn) return <Coord>[];

    final moves = <Coord>[];
    // 四方向：上 下 左 右
    const dirs = <(int, int)>[(-1, 0), (1, 0), (0, -1), (0, 1)];

    for (final d in dirs) {
      final nr = piece.position.row + d.$1;
      final nc = piece.position.col + d.$2;

      // 边界检查
      if (nr < 0 || nr >= kBoardRows || nc < 0 || nc >= kBoardCols) continue;

      final targetIdx = coordIndex(nr, nc);

      // === 己方兽穴：禁止进入 ===
      if (piece.color == PlayerColor.blue && targetIdx == kBlueDen) continue;
      if (piece.color == PlayerColor.red && targetIdx == kRedDen) continue;

      // === 鼠标克象判定：riverLand 边界（仅鼠需要）===
      // 鼠不能从陆地走到河里 / 从河里走到陆地
      if (piece.animal == Animal.rat &&
          isRiver(piece.position.index) != isRiver(targetIdx)) {
        continue;
      }

      // === 狮 / 虎河跳：相邻格是河时触发跳越 ===
      if ((piece.animal == Animal.lion || piece.animal == Animal.tiger) &&
          isRiver(targetIdx)) {
        moves.addAll(_getRiverJumps(state, piece, d.$1, d.$2));
        continue;
      }

      // === 非鼠不能入水（鼠前面已放行；狮/虎通过跳越也已处理）===
      if (isRiver(targetIdx) && piece.animal != Animal.rat) continue;

      // === 己方棋子阻挡 ===
      final target = state.pieces[targetIdx];
      if (target != null && target.isAlive && target.color == piece.color) continue;

      if (target == null || !target.isAlive) {
        // 空格
        moves.add((row: nr, col: nc));
      } else if (canCapture(piece, target)) {
        // 可吃子
        moves.add((row: nr, col: nc));
      }
    }

    return moves;
  }

  // ============================================================
  // 吃子判定
  // ============================================================

  /// 判断 [attacker] 能否吃掉 [defender]
  ///
  /// 判定顺序（按参考 Java 实现）：
  /// 1. 水陆同介质约束（鼠专属 — 鼠不能从河吃岸 / 从岸吃河）
  ///    注意：陆→河 / 河→陆 的位移已在 getValidMoves 中由"鼠不能入水"过滤，
  ///    这里专门处理**鼠从河吃河中其他鼠** 的合法场景：双方都在河里，可以吃。
  /// 2. 鼠吃象特例
  /// 3. 象不吃鼠特例（除非鼠在陷阱中）
  /// 4. 通用规则：attacker.rank >= defender.effectiveRank（陷阱中→0）
  static bool canCapture(Piece attacker, Piece defender) {
    if (defender.color == attacker.color) return false;

    // === 1. 鼠的水陆边界：鼠只能与同介质目标交战 ===
    if (attacker.animal == Animal.rat &&
        isRiver(attacker.position.index) != isRiver(defender.position.index)) {
      return false;
    }

    // === 2. 鼠吃象特例（不受 rank 限制）===
    if (attacker.animal == Animal.rat && defender.animal == Animal.elephant) {
      return true;
    }

    // === 3. 象不吃鼠特例（除非鼠在陷阱中） ===
    // 鼠在陷阱中 → defenseRank=0 → 不等 RAT.ordinal()=1 → 通过
    // 鼠不在陷阱 → defenderRank=1=RAT.ordinal() → return false
    if (attacker.animal == Animal.elephant && defender.animal == Animal.rat) {
      // 计算 defender 的 effective rank（陷阱降级）
      final defenderRank = _effectiveRank(defender);
      if (defenderRank == Animal.rat.rank) return false; // 鼠不在陷阱，象不吃
    }

    // === 4. 通用规则：attacker.rank >= defender.effectiveRank ===
    return attacker.animal.rank >= _effectiveRank(defender);
  }

  /// 棋子的有效防御等级：若在对方陷阱上 → 0；否则 → 攻击等级
  ///
  /// 注意：是**对方陷阱**（isEnemyTrap）。即己方的棋子在**对方**陷阱中时降级。
  /// 例如蓝方的狼踩到红方陷阱 `{2,4,10}` → effectiveRank=0。
  static int _effectiveRank(Piece piece) {
    final idx = piece.position.index;
    final inEnemyTrap = (piece.color == PlayerColor.blue && isRedTrap(idx)) ||
        (piece.color == PlayerColor.red && isBlueTrap(idx));
    return inEnemyTrap ? 0 : piece.animal.rank;
  }

  // ============================================================
  // 狮 / 虎河跳
  // ============================================================

  /// 沿 (dr, dc) 方向寻找河跳落点
  ///
  /// 跳跃距离（按参考实现）：
  /// - 纵向 (±7)：跨 3 个河格，落 +4*offset（落点在对岸）
  /// - 横向 (±1)：跨 2 个河格，落 +3*offset
  ///
  /// 河中若有棋子（实际只可能是鼠）阻挡 → 该方向无走法。
  static List<Coord> _getRiverJumps(
    GameState state,
    Piece piece,
    int dr,
    int dc,
  ) {
    final jumps = <Coord>[];
    // 纵向跳 3 个河格后落在 +4 offset，横向跳 2 个河格后落在 +3 offset
    final stepsToCross = dc == 0 ? 3 : 2;
    int r = piece.position.row + dr;
    int c = piece.position.col + dc;

    // 检查前 stepsToCross 格：必须都是河，且河中无棋子
    for (int i = 0; i < stepsToCross; i++) {
      if (r < 0 || r >= kBoardRows || c < 0 || c >= kBoardCols) {
        return jumps; // 越界
      }
      final idx = coordIndex(r, c);
      if (!isRiver(idx)) return jumps; // 中间断河，跳越失败
      final blocker = state.pieces[idx];
      if (blocker != null && blocker.isAlive) {
        return jumps; // 河中棋子阻挡（只可能是鼠）
      }
      r += dr;
      c += dc;
    }

    // 落点 = 跨河后的第一格
    if (r < 0 || r >= kBoardRows || c < 0 || c >= kBoardCols) return jumps;
    final dropIdx = coordIndex(r, c);

    // 不能落入己方兽穴
    if (piece.color == PlayerColor.blue && dropIdx == kBlueDen) return jumps;
    if (piece.color == PlayerColor.red && dropIdx == kRedDen) return jumps;

    final target = state.pieces[dropIdx];
    if (target == null || !target.isAlive) {
      // 空格 → 直接落
      jumps.add((row: r, col: c));
    } else if (target.color != piece.color && canCapture(piece, target)) {
      // 敌方棋子 → 可吃
      jumps.add((row: r, col: c));
    }
    // 己方棋子占据 → 不能落

    return jumps;
  }

  /// 公开包装器：返回 [piece] 在所有四个方向的河跳落点
  static List<Coord> getRiverJumps(GameState state, Piece piece) {
    const dirs = <(int, int)>[(-1, 0), (1, 0), (0, -1), (0, 1)];
    final jumps = <Coord>[];
    for (final d in dirs) {
      jumps.addAll(_getRiverJumps(state, piece, d.$1, d.$2));
    }
    return jumps;
  }

  // ============================================================
  // 执行走子
  // ============================================================

  /// 执行一步棋
  ///
  /// 返回新的 [GameState]；若 [from] 无棋子、棋子不属于当前回合方、
  /// 或 [to] 不合法则返回 `null`。
  static GameState? movePiece(GameState state, Coord from, Coord to) {
    final fromIdx = from.index;
    final piece = state.pieces[fromIdx];
    if (piece == null || !piece.isAlive) return null;
    if (piece.color != state.currentTurn) return null;

    // 验证目标合法性
    final validMoves = getValidMoves(state, from);
    if (!validMoves.any((m) => m.row == to.row && m.col == to.col)) return null;

    final toIdx = to.index;
    final captured = state.pieces[toIdx];
    final isRiverJump = (piece.animal == Animal.lion ||
            piece.animal == Animal.tiger) &&
        ((from.row - to.row).abs() > 1 || (from.col - to.col).abs() > 1);

    // 构造新棋盘 → 移除原位置 → 棋子放入目标格（覆盖被吃子）
    final newPieces = Map<int, Piece>.from(state.pieces);
    newPieces.remove(fromIdx);
    newPieces[toIdx] = piece.copyWith(position: to);

    final move = Move(
      from: from,
      to: to,
      animal: piece.animal,
      isRiverJump: isRiverJump,
      captured: (captured != null && captured.isAlive) ? captured : null,
      roundNumber: state.history.length + 1,
    );

    // 换手（先换再判）
    final nextTurn = state.currentTurn == PlayerColor.blue
        ? PlayerColor.red
        : PlayerColor.blue;
    var newState = state.copyWith(
      pieces: newPieces,
      currentTurn: nextTurn,
      history: [...state.history, move],
    );

    // 走完后检查胜负（在换手之后的状态上检查"下一手方"是否无子可走）
    final end = checkGameEnd(newState);
    if (end.isOver) {
      newState = newState.copyWith(winner: end.winner, gameOverReason: end.reason);
    }

    return newState;
  }

  // ============================================================
  // 胜负判定
  // ============================================================

  /// 判定当前 [state] 是否结束
  ///
  /// 在 `movePiece` 中调用时，[state] 已经是**换手后**的状态（currentTurn 是
  /// "下一手方"）。所以：
  /// - "当前手方" 在这里实际是**刚落子的对手**（被判定的一方）
  /// - "下一手方" 在这里是**该走而还没走的人**（检查他无子可走）
  ///
  /// 标准胜负（参考 Java `BoardUtils.isGameOverScenario`）：
  /// 1. 进入对方兽穴 → **走子方** 赢（即"当前手方"为**对手** → 走子方赢 = currentTurn 反方）
  /// 2. 棋子全灭 → 棋子没了的方输
  /// 3. 无子可走 → 当前手方（即将走子的人）输
  static ({bool isOver, PlayerColor? winner, String? reason}) checkGameEnd(
    GameState state,
  ) {
    // state.currentTurn 是刚落子后的下一手方
    final justMoved = state.currentTurn == PlayerColor.blue
        ? PlayerColor.red
        : PlayerColor.blue;
    final nextToMove = state.currentTurn;

    // 1. 进入对方兽穴：走子方（justMoved）走到对方兽穴 → 走子方赢
    //    蓝穴(59) 被红方占据 → 蓝方输 → 红方赢
    //    红穴(3) 被蓝方占据 → 红方输 → 蓝方赢
    if (state.pieces.containsKey(kBlueDen) &&
        state.pieces[kBlueDen]?.color == PlayerColor.red) {
      return (isOver: true, winner: PlayerColor.red, reason: '蓝穴被入侵');
    }
    if (state.pieces.containsKey(kRedDen) &&
        state.pieces[kRedDen]?.color == PlayerColor.blue) {
      return (isOver: true, winner: PlayerColor.blue, reason: '红穴被入侵');
    }

    // 2. 棋子全灭：某方没有存活棋子 → 该方输
    bool blueAlive = false;
    bool redAlive = false;
    for (final p in state.pieces.values) {
      if (!p.isAlive) continue;
      if (p.color == PlayerColor.blue) {
        blueAlive = true;
      } else {
        redAlive = true;
      }
    }
    if (!blueAlive) {
      return (isOver: true, winner: PlayerColor.red, reason: '蓝方棋子全灭');
    }
    if (!redAlive) {
      return (isOver: true, winner: PlayerColor.blue, reason: '红方棋子全灭');
    }

    // 3. 无子可走：下一手方（nextToMove）所有棋子都不能动 → 下一手方输
    bool nextCanMove = false;
    for (final p in state.pieces.values) {
      if (!p.isAlive) continue;
      if (p.color != nextToMove) continue;
      final moves = getValidMoves(state, p.position);
      if (moves.isNotEmpty) {
        nextCanMove = true;
        break;
      }
    }
    if (!nextCanMove) {
      // 下一手方输 → 刚走子方赢
      return (isOver: true, winner: justMoved, reason: '对手无子可走');
    }

    // 4. 150 回合上限（300 步）和棋
    if (state.roundCount >= kMaxRounds * 2) {
      return (isOver: true, winner: null, reason: '回合上限');
    }

    return (isOver: false, winner: null, reason: null);
  }

  // ============================================================
  // 悔棋
  // ============================================================

  /// 悔棋 N 步
  ///
  /// 从 history 栈顶依次弹出，恢复棋盘与回合状态。
  /// 若 history 不足 [steps] 步，返回原状态不变。
  static GameState undoMoves(GameState state, int steps) {
    if (state.history.length < steps) return state;

    var s = state;
    for (int i = 0; i < steps; i++) {
      final last = s.history.last;

      // 反放棋子
      final pieces = Map<int, Piece>.from(s.pieces);
      pieces.remove(last.to.index);

      // 恢复移动的棋子到原位
      // s.currentTurn 是下一步走子方，上一步走子方为 opposite
      final moveColor = s.currentTurn == PlayerColor.blue
          ? PlayerColor.red
          : PlayerColor.blue;
      pieces[last.from.index] = Piece(
        animal: last.animal,
        color: moveColor,
        position: last.from,
      );

      // 恢复被吃棋子
      if (last.captured != null) {
        pieces[last.to.index] = last.captured!;
      }

      s = s.copyWith(
        pieces: pieces,
        currentTurn: moveColor,
        history: s.history.sublist(0, s.history.length - 1),
        winner: null,
        gameOverReason: null,
      );
    }

    return s;
  }
}