import '../models/game_state.dart';
import '../surround_game_constants.dart';
import 'bfs_pathfinder.dart';

/// QuoridorEngine — 全静态、纯函数
///
/// 职责：
///   1. 初始化棋盘（邻接表 + 墙壁数组 + 棋子起点）
///   2. 走棋（含跳跃规则）
///   3. 放墙（含合法性校验）
///   4. 邻接表更新（墙壁切断格子间连接）
///   5. 胜负判定（含平局）
///   6. 换手（重算 validMoves）
///
/// Swift 对应：
///   GameModel.swift — initModelData, iMove, iPutWall, iWallIsAllow, status
///   GameModel+Action.swift — removeNearLink, addNearLink
///   GameModel+Logic.swift — scopeForPlayer
///
/// 设计约束：
///   - 不持有状态，所有方法形如 (state, args) -> newState
///   - 失败用 null（如非法放墙）— 不抛异常，方便业务逻辑短路
///   - 墙壁校验的"试探"通过深拷贝 adjacency 实现（O(81) 拷贝，可接受）
class QuoridorEngine {
  QuoridorEngine._();

  // ═══════════════════════ 初始化 ═══════════════════════

  /// 创建初始 GameState
  ///
  /// - 邻接表 81 个，标准四连通
  /// - wallGrid 289 个 false
  /// - top 在 cellId=4 (x=4,y=0), bottom 在 cellId=76 (x=4,y=8)
  /// - currentPlayerIsTop=true（先手固定，Swift 用 arc4random，为单测可复现改为固定）
  /// - status=running
  /// - validMoves 已按初始局面计算
  /// - history 为空
  ///
  /// Swift 参考：GameModel.swift:161-173 initModelData
  static GameState initialize() {
    final adj = buildInitialAdjacency();
    final walls = List.filled(SurroundGameConstants.totalWallCells, false);
    final topId = SurroundGameConstants.topPlayerStart;
    final bottomId = SurroundGameConstants.bottomPlayerStart;

    // 计算初始可走范围（棋盘空，无跳跃）
    final moves = getValidMoves(adj, topId, bottomId);

    return GameState(
      adjacency: adj,
      wallGrid: walls,
      topPlayerId: topId,
      bottomPlayerId: bottomId,
      currentPlayerIsTop: true,
      topWallsPlaced: 0,
      bottomWallsPlaced: 0,
      history: const [],
      status: GameStatus.running,
      validMoves: moves,
    );
  }

  /// 测试用工厂：从扁平参数构造特定局面
  ///
  /// 先建初始邻接表，然后依次 applyWallToAdjacency 处理 placedWalls。
  /// 不会自动计算 validMoves（留给调用者或 switchTurn）。
  /// validMoves 初始设置为空（调用方需自行计算）。
  ///
  /// [placedWalls] 参数类型使用 record 语法：每个元素是 (x, y, WallOrientation)
  static GameState fromBoardSpec({
    required int topPlayerId,
    required int bottomPlayerId,
    required bool currentPlayerIsTop,
    List<({int x, int y, WallOrientation o})> placedWalls = const [],
    int topWallsPlaced = 0,
    int bottomWallsPlaced = 0,
  }) {
    var adj = buildInitialAdjacency();
    final walls = List.filled(SurroundGameConstants.totalWallCells, false);

    for (final wall in placedWalls) {
      // 标记墙壁占用
      for (final wid in wallOccupiedCells(wall.x, wall.y, wall.o)) {
        walls[wid] = true;
      }
      // 切断邻接
      adj = applyWallToAdjacency(adj, wall.x, wall.y, wall.o, true);
    }

    return GameState(
      adjacency: adj,
      wallGrid: walls,
      topPlayerId: topPlayerId,
      bottomPlayerId: bottomPlayerId,
      currentPlayerIsTop: currentPlayerIsTop,
      topWallsPlaced: topWallsPlaced,
      bottomWallsPlaced: bottomWallsPlaced,
      history: const [],
      status: GameStatus.running,
      validMoves: {},
    );
  }

  /// 构建初始 81 长度邻接表（标准四连通）
  ///
  /// 每个格子连接上下左右四个方向中存在的邻居。
  /// cellId = x + y*9。
  ///
  /// Swift 参考：GameModel.swift:186-202 initGameNearsAndWalls
  static List<Set<int>> buildInitialAdjacency() {
    final adj = List.generate(81, (i) => <int>{});
    for (int i = 0; i < 81; i++) {
      final x = i % 9;
      final y = i ~/ 9;
      if (x > 0) adj[i].add(i - 1);
      if (x < 8) adj[i].add(i + 1);
      if (y > 0) adj[i].add(i - 9);
      if (y < 8) adj[i].add(i + 9);
    }
    return adj;
  }

  // ═══════════════════════ 墙壁 ID 计算 ═══════════════════════

  /// 墙壁基址 ID（在 17×17 wallGrid 中的中心位置）
  ///
  /// 公式：wallId = (x*2+1) + (y*2+1)*17
  /// 其中 x,y ∈ [0,7]（墙壁坐标不能到 8，否则越界）。
  ///
  /// Swift 参考：DataModel.swift:82-94 updateWallIds
  ///
  /// 注意：Swift 里 x,y ∈ [0,8] 的检查会允许 x=8 的情况，
  /// 此时 (8*2+1)+(y*2+1)*17 = 17+... ≥ 289 = 越界。
  /// 本实现修正为 x,y ∈ [0,7] 的限制。
  static int wallBaseId(int x, int y) {
    // x,y 已在 isWallPlacementValid 中检查 [0,7]
    return (x * 2 + 1) + (y * 2 + 1) * 17;
  }

  /// 墙壁占用的 3 个 wallGrid 单元
  ///
  /// 横向 (horizontal): [baseId-1, baseId, baseId+1]
  ///   （同行三列，Swift h=true → wallId += i, i∈[-1,0,1]）
  /// 竖向 (vertical):   [baseId-17, baseId, baseId+17]
  ///   （同列三行，Swift h=false → wallId += i*17, i∈[-1,0,1]）
  ///
  /// Swift 参考：DataModel.swift:82-94 updateWallIds
  static List<int> wallOccupiedCells(int x, int y, WallOrientation orientation) {
    final base = wallBaseId(x, y);
    if (orientation == WallOrientation.horizontal) {
      return [base - 1, base, base + 1];
    } else {
      return [base - 17, base, base + 17];
    }
  }

  // ═══════════════════════ 邻接表更新 ═══════════════════════

  /// 更新邻接表（切断或恢复 2 对相邻格子之间的连接）
  ///
  /// 返回新的 adjacency 列表（深拷贝原始 Set 到新的 Set），不修改入参。
  ///
  /// 横向墙 (horizontal)，用 wall.id = x + y*9：
  ///   切断 (id, id+9)  与 (id+1, id+10)
  ///   — 阻止穿越横墙的上下走动
  /// 竖向墙 (vertical)：
  ///   切断 (id, id+1)  与 (id+9, id+10)
  ///   — 阻止穿越竖墙的左右走动
  ///
  /// [isPlacing] = true 表示切断，false 表示恢复。
  ///
  /// Swift 参考：GameModel+Action.swift:23-52 removeNearLink / addNearLink
  ///
  /// 注意这里的 id 用的是 x + y*9（棋格坐标），不是 wallGrid 里的索引。
  static List<Set<int>> applyWallToAdjacency(
    List<Set<int>> adjacency, int x, int y,
    WallOrientation orientation, bool isPlacing,
  ) {
    final id = x + y * 9; // 棋格坐标（不是 wallGrid 索引）

    // 深拷贝：把每个 Set<int> 复制为新 Set
    final result = adjacency.map((set) => set.toSet()).toList();

    void toggle(int a, int b) {
      if (isPlacing) {
        result[a].remove(b);
        result[b].remove(a);
      } else {
        result[a].add(b);
        result[b].add(a);
      }
    }

    if (orientation == WallOrientation.horizontal) {
      // 横向墙：切断 (id, id+9) 和 (id+1, id+10)
      // 对应 Swift removeNearLink: wall.h → 用 wall.id
      if (id + 9 < 81) toggle(id, id + 9);
      if (id + 1 < 81 && id + 10 < 81) toggle(id + 1, id + 10);
    } else {
      // 竖向墙：切断 (id, id+1) 和 (id+9, id+10)
      if (id + 1 < 81) toggle(id, id + 1);
      if (id + 9 < 81 && id + 10 < 81) toggle(id + 9, id + 10);
    }

    return result;
  }

  // ═══════════════════════ 走棋 ═══════════════════════

  /// 移动当前玩家的棋子到 targetCellId
  ///
  /// 校验：
  ///   - targetCellId 必须在 state.validMoves 中
  ///   - 不切换回合（调用方需要 switchTurn）
  ///
  /// 更新：
  ///   - topPlayerId / bottomPlayerId
  ///   - history 追加 MoveRecord
  ///
  /// 返回 null 表示非法移动
  ///
  /// Swift 参考：GameModel.swift:21-28 iMove / iMoveWithId
  static GameState? movePiece(GameState state, int targetCellId) {
    if (!state.validMoves.contains(targetCellId)) return null;

    final record = MoveRecord.move(
      cellId: targetCellId,
      isTopPlayer: state.currentPlayerIsTop,
    );

    final newHistory = [...state.history, record];

    if (state.currentPlayerIsTop) {
      return state.copyWith(
        topPlayerId: targetCellId,
        history: newHistory,
      );
    } else {
      return state.copyWith(
        bottomPlayerId: targetCellId,
        history: newHistory,
      );
    }
  }

  // ═══════════════════════ 跳跃规则 ═══════════════════════

  /// 计算指定玩家的可走格子集合（含跳跃规则）
  ///
  /// 直跳规则（Swift scopeForPlayer）：
  ///   遍历 player 的邻接格子：
  ///     如果邻接格 ≠ 对手：加入结果
  ///     如果邻接格 = 对手：把对手的邻接格也加入（跳过去）
  ///
  /// 不实现官方斜跳规则（符合"Swift 忠实移植"决策）。
  ///
  /// Swift 参考：GameModel+Logic.swift:6-20 scopeForPlayer
  static Set<int> getValidMoves(
    List<Set<int>> adjacency, int playerId, int opponentId,
  ) {
    final moves = <int>{};
    for (final near in adjacency[playerId]) {
      if (near != opponentId) {
        moves.add(near);
      } else {
        // 对手在邻接格 → 把对手邻接格加入（跳过）
        for (final rivalNear in adjacency[opponentId]) {
          if (rivalNear != playerId) {
            moves.add(rivalNear);
          }
        }
      }
    }
    return moves;
  }

  // ═══════════════════════ 换手 ═══════════════════════

  /// 重算"某方回合"的派生量：currentPlayerIsTop + validMoves + status。
  ///
  /// [switchTurn] 与 [replayHistory] 共用：前者翻手，后者按棋谱显式指定。
  static GameState _recomputeTurn(GameState state, bool currentPlayerIsTop) {
    final playerId =
        currentPlayerIsTop ? state.topPlayerId : state.bottomPlayerId;
    final opponentId =
        currentPlayerIsTop ? state.bottomPlayerId : state.topPlayerId;

    final moves = getValidMoves(state.adjacency, playerId, opponentId);
    final status = checkStatus(
      state.adjacency, state.topPlayerId, state.bottomPlayerId,
    );

    return state.copyWith(
      currentPlayerIsTop: currentPlayerIsTop,
      validMoves: moves,
      status: status,
    );
  }

  /// 切换回合 —— 委托 [_recomputeTurn]（行为与重构前完全一致）。
  ///
  /// 不在 movePiece/placeWall 里自动换手是为了：
  ///   1. 让单测能分别验证"动作"和"换手"
  ///   2. 让网络层有机会在换手前广播状态
  ///
  /// Swift 参考：GameModel.swift:117-120 player 属性
  ///   Swift 通过 gameStack.count 的奇偶判断，我们显式翻转 counter
  static GameState switchTurn(GameState state) =>
      _recomputeTurn(state, !state.currentPlayerIsTop);

  // ═══════════════════════ 胜负判定 ═══════════════════════

  /// 检查游戏状态
  ///
  /// 规则（Swift 忠实移植）：
  ///   1. topPlayerId 到达 y=8（cellId ≥ 72）→ topWin
  ///      除非 bottomPlayer 只剩 1 步 = 平局（Swift GameModel.swift:124-138）
  ///   2. bottomPlayerId 到达 y=0（cellId ≤ 8）→ bottomWin
  ///      除非 topPlayer 只剩 1 步 = 平局
  ///   3. 否则 → running
  ///
  /// 平局条件（对应 Swift status 的 Draw）：
  ///   赢家到达终点、同时输家路径长度 = 1（即下一步就到）
  ///
  /// Swift 参考：GameModel.swift:123-139 status
  static GameStatus checkStatus(
    List<Set<int>> adjacency,
    int topPlayerId,
    int bottomPlayerId,
  ) {
    if (topPlayerId >= 72) {
      final bottomPath = BfsPathfinder.findShortestPath(
        adjacency, bottomPlayerId, false,
      );
      if (bottomPath.length == 1) {
        return GameStatus.draw; // bottom 只剩 1 步 → 平局
      }
      return GameStatus.topWin;
    }
    if (bottomPlayerId <= 8) {
      final topPath = BfsPathfinder.findShortestPath(
        adjacency, topPlayerId, true,
      );
      if (topPath.length == 1) {
        return GameStatus.draw; // top 只剩 1 步 → 平局
      }
      return GameStatus.bottomWin;
    }
    return GameStatus.running;
  }

  // ═══════════════════════ 放墙 ═══════════════════════

  /// 放置墙壁（含完整合法性校验）
  ///
  /// 1. 校验合法性（通过 isWallPlacementValid）
  /// 2. 校验通过：
  ///    - 更新 wallGrid（三格占满）
  ///    - 更新 adjacency（切断两对格子连接）
  ///    - 追加 MoveRecord
  ///    - 对应玩家墙计数 +1
  /// 3. 校验失败：返回 null
  ///
  /// 注意：不切换回合（调用方需要 switchTurn）。
  ///
  /// Swift 参考：GameModel.swift:9-18 iPutWall
  static GameState? placeWall(
    GameState state, int x, int y, WallOrientation orientation,
  ) {
    // 检查墙壁数是否用完
    final placed = state.currentPlayerIsTop
        ? state.topWallsPlaced
        : state.bottomWallsPlaced;
    if (placed >= SurroundGameConstants.wallCountPerPlayer) return null;

    if (!isWallPlacementValid(
      state.wallGrid, state.adjacency,
      state.topPlayerId, state.bottomPlayerId,
      x, y, orientation,
    )) {
      return null;
    }

    // 更新 wallGrid
    final newWalls = [...state.wallGrid];
    for (final wid in wallOccupiedCells(x, y, orientation)) {
      newWalls[wid] = true;
    }

    // 更新 adjacency（切断）
    final newAdj = applyWallToAdjacency(
      state.adjacency, x, y, orientation, true,
    );

    // 记录
    final record = MoveRecord.wall(
      x: x, y: y, orientation: orientation,
      isTopPlayer: state.currentPlayerIsTop,
    );
    final newHistory = [...state.history, record];

    // 更新墙壁计数
    final topPlaced = state.currentPlayerIsTop
        ? state.topWallsPlaced + 1
        : state.topWallsPlaced;
    final bottomPlaced = state.currentPlayerIsTop
        ? state.bottomWallsPlaced
        : state.bottomWallsPlaced + 1;

    return state.copyWith(
      wallGrid: newWalls,
      adjacency: newAdj,
      history: newHistory,
      topWallsPlaced: topPlaced,
      bottomWallsPlaced: bottomPlaced,
    );
  }

  // ═══════════════════════ 棋谱重放（信任棋谱，仅几何） ═══════════════════════

  /// 应用单条 [MoveRecord] 重建棋盘几何 —— 信任棋谱、不复验合法性。
  ///
  /// 与 [movePiece]/[placeWall] 的区别：
  ///   - 不校验合法性（棋谱来自合法对局，是权威）
  ///   - 行动方取自 [MoveRecord.isTopPlayer]，而非 state.currentPlayerIsTop
  ///   - 不翻回合、不算 validMoves（与"动作 vs 换手分离"约定一致）
  ///
  /// 走棋：解码 cellId = x + y*9，更新对应棋子位置。
  /// 放墙：标记 wallGrid、切断邻接、墙计数 +1。
  /// orientation 缺失（畸形棋谱）时仅追加 history、不改几何（防御）。
  static GameState applyMoveRecord(GameState state, MoveRecord record) {
    final newHistory = [...state.history, record];

    if (!record.isWall) {
      final cellId = record.x + record.y * 9;
      if (record.isTopPlayer) {
        return state.copyWith(topPlayerId: cellId, history: newHistory);
      }
      return state.copyWith(bottomPlayerId: cellId, history: newHistory);
    }

    final o = record.orientation;
    if (o == null) {
      return state.copyWith(history: newHistory);
    }

    final newWalls = [...state.wallGrid];
    for (final wid in wallOccupiedCells(record.x, record.y, o)) {
      newWalls[wid] = true;
    }
    final newAdj = applyWallToAdjacency(state.adjacency, record.x, record.y, o, true);
    final topPlaced = record.isTopPlayer ? state.topWallsPlaced + 1 : state.topWallsPlaced;
    final bottomPlaced = record.isTopPlayer ? state.bottomWallsPlaced : state.bottomWallsPlaced + 1;

    return state.copyWith(
      wallGrid: newWalls,
      adjacency: newAdj,
      history: newHistory,
      topWallsPlaced: topPlaced,
      bottomWallsPlaced: bottomPlaced,
    );
  }

  /// 从棋谱 [history] 重建完整 GameState（信任棋谱、仅几何）。
  ///
  /// [upTo] = 光标（已应用步数）：0=开局、length=终局；缺省=全量。越界自动 clamp。
  /// 步退无需逆操作：cursor 10→5 只需 `replayHistory(h, upTo: 5)`。
  ///
  /// 流程：initialize() → 逐条 applyMoveRecord → 末尾 [_recomputeTurn] 重算回合/可走/状态。
  /// 回合派生自最后一手：n=0 → top 先手；否则 = !history[n-1].isTopPlayer。
  static GameState replayHistory(List<MoveRecord> history, {int? upTo}) {
    final n = upTo == null ? history.length : upTo.clamp(0, history.length);
    var state = initialize();
    for (var i = 0; i < n; i++) {
      state = applyMoveRecord(state, history[i]);
    }
    final isTop = (n == 0) ? true : !history[n - 1].isTopPlayer;
    return _recomputeTurn(state, isTop);
  }

  // ═══════════════════════ 墙壁合法性校验 ═══════════════════════

  /// 墙壁合法性校验 — 三道关
  ///
  /// 1. (x, y) 在 [0, 7] 范围内（修正 Swift 的 [0,8] 越界 bug）
  /// 2. 拟占用的 3 个 wallGrid 单元均未被占用
  /// 3. 模拟切断邻接后，双方仍有路径到自己的终点
  ///
  /// 实现：深拷贝 adjacency → applyWallToAdjacency → bothPlayersHavePath
  ///       整个过程不污染传入的 state。
  ///
  /// Swift 参考：GameModel.swift:61-78 iWallIsAllow
  static bool isWallPlacementValid(
    List<bool> wallGrid, List<Set<int>> adjacency,
    int topPlayerId, int bottomPlayerId,
    int x, int y, WallOrientation orientation,
  ) {
    // 关 1: 坐标范围
    if (x < 0 || x > 7 || y < 0 || y > 7) return false;

    // 关 2: 墙壁不重叠
    for (final wid in wallOccupiedCells(x, y, orientation)) {
      if (wid < 0 || wid >= wallGrid.length) return false; // 越界保护
      if (wallGrid[wid]) return false;
    }

    // 关 3: 试探切断后双方仍有路径
    final testAdj = applyWallToAdjacency(
      adjacency, x, y, orientation, true,
    );

    return BfsPathfinder.bothPlayersHavePath(
      testAdj, topPlayerId, bottomPlayerId,
    );
  }
}
