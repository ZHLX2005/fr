# Quoridor 引擎重写 — 设计文档

- **日期**：2026-06-12
- **范围**：`lib/core/surround_game/` 引擎层（不含 UI、不含 LAN 网络协议改造）
- **目标**：把现有"围追堵截"（20×15 + 同时走 + 留轨迹）替换为 Quoridor（9×9 + 轮流走 + 放墙）
- **参考实现**：`.claude/repo/Quoridor-ios/`（Swift 版本，作为唯一规则真值源）
- **预计工作量**：~5 小时（分 6 阶段 + 7 次 commit）

---

## 1. 决策快照

| 维度 | 决策 | 备注 |
|------|------|------|
| 交付范围 | 引擎优先（纯引擎 + 单测，无 UI、无 Service 改造、无 LAN 协议改造） | 下一轮做 UI，再下一轮做 LAN 同步 |
| 规则保真度 | Swift 忠实移植 | 直跳（不实现官方斜跳）、`对方剩 1 步 → 平局`、其他状态按 Swift |
| 旧 UI/Service 收敛 | 旧文件移到 `_legacy/`，主导出只指向新模块 | 下轮 UI 完成后整体删除 |
| AI 是否在范围 | 不含 | 只做 BFS 三件套；`findAllPaths` 不实现 |

---

## 2. 与现状的差异

| 维度 | 现有实现 | Quoridor（目标） |
|------|---------|-----------------|
| 棋盘 | 20×15 带边界 | 9×9 无边障 |
| 网格 | 单层 `List<List<CellState>>` | 双网格：邻接表 81 + 墙壁 289 |
| 回合 | 双方同步 | 轮流单方 |
| 动作 | 只能走棋 | 走 1 步 / 放 1 墙 二选一 |
| 墙壁 | 无 | 每人 10 块 |
| 轨迹 | 留下轨迹不可穿越 | 无轨迹，靠墙壁阻挡 |
| 跳跃 | 无 | 直跳（对手相邻时跳过其后一格） |
| 胜利 | 把对方逼入死角 | 先到对方底线 |
| 寻路 | 无 | BFS 最短路径（路径验证 + 合法性核心） |
| 网络 | HTTP `executeMove(hostDir, clientDir)` 同步 | 本轮**不动**，下轮重做 |

---

## 3. 文件清单

### 3.1 新结构

```
lib/core/surround_game/
├── surround_game.dart                       # ✏️ 修改：导出指向新模块
├── surround_game_constants.dart             # ✏️ 全改
├── surround_game_service.dart               # ✏️ 局部：删 executeMove，sync/input 改 noop
├── models/
│   ├── game_room.dart                       # ✅ 不动
│   ├── player_input.dart                    # ✅ 不动（保留供下轮 LAN）
│   ├── game_state.dart                      # 🆕 全新：immutable GameState + MoveRecord
│   └── game_event.dart                      # 🆕 全新：sealed GameEvent
├── engine/
│   ├── bfs_pathfinder.dart                  # 🆕 全新
│   └── game_engine.dart                     # 🆕 全新
├── pages/
│   ├── game_lobby_page.dart                 # ✏️ 局部：跳转到 PlaceholderPage
│   └── game_room_page.dart                  # ✏️ 局部：同上
├── widgets/
│   └── room_list_tile.dart                  # ✅ 不动
└── _legacy/                                  # 🆕 新建
    ├── README.md
    ├── direction_pad.dart
    ├── game_board_widget.dart
    ├── game_board_page.dart
    ├── game_engine.dart                      # 旧版（含 step/collision）
    ├── collision_detector.dart
    ├── game_state.dart                       # 旧版
    └── game_event.dart                       # 旧版

test/core/surround_game/
├── bfs_pathfinder_test.dart                  # 10 用例
├── game_engine_test.dart                     # 26 用例
└── game_state_test.dart                      # 6 用例
```

### 3.2 `_legacy/` 约束

- `_` 前缀确保不被 `surround_game.dart` 导出
- 内部 import 自洽（旧 page 引用旧 widget/engine/state，全在 `_legacy/` 内）
- 下轮 UI 完成后整体 `rm -r _legacy/`

---

## 4. 常量与枚举

文件：`lib/core/surround_game/surround_game_constants.dart`

```dart
class SurroundGameConstants {
  SurroundGameConstants._();

  // ─── 棋盘尺寸 ───
  static const int boardSize = 9;
  static const int totalCells = 81;          // 0..80
  static const int wallGridSize = 17;
  static const int totalWallCells = 289;     // 0..288
  static const int wallCountPerPlayer = 10;

  // ─── 起始位置（Swift GameModel.swift:163-164）───
  // cellId = x + y * 9
  static const int topPlayerStart = 4;       // x=4, y=0
  static const int bottomPlayerStart = 76;   // x=4, y=8

  // ─── 胜负目标行 ───
  // top 到达 y=8 → cellId ∈ [72, 80]
  // bottom 到达 y=0 → cellId ∈ [0, 8]
  static const int topGoalRow = 8;
  static const int bottomGoalRow = 0;

  // ─── 保留：surround_game_service 仍在用 ───
  static const String kPathGameInfo = '/api/game/info';
  static const String kPathGameJoin = '/api/game/join';
  static const String kPathGameLeave = '/api/game/leave';
  static const String kPathGameSync = '/api/game/sync';   // noop 期
  static const String kPathGameInput = '/api/game/input'; // noop 期
  static const String kBroadcastGame = 'g';
  static const String kBroadcastRoom = 'r';
  static const String kBroadcastPlayers = 'p';
  static const String kGameType = 'surround';
  static const int kMaxPlayers = 2;
}

/// 墙壁方向
enum WallOrientation { horizontal, vertical }

/// 玩家当前回合的动作选择（UI 层用，引擎不强依赖）
enum TurnAction { move, placeWall }

/// 游戏状态
///
/// 注：Swift 拼写为 `Runing`（typo），新 Dart 代码改为正确的 `running`。
enum GameStatus { running, topWin, bottomWin, draw }

/// 格子状态（UI 渲染用）
enum CellState {
  empty,
  playerTop,
  playerBottom,
  validMove,
  invalidWall,
}
```

### 关键设计点

1. **`topPlayerStart / bottomPlayerStart` 直接是 cellId**，避免业务层做 `x + y*9` 计算
2. **`totalCells` / `totalWallCells` 显式提供**，避免业务层魔法数 81、289
3. **Swift `Runing` → Dart `running`**（修正拼写）
4. **保留旧网络常量**：`surround_game_service` 还在跑 LAN 发现，不能动

---

## 5. 数据模型

### 5.1 `GameState`（`models/game_state.dart`）

```dart
/// QuoridorState — 不可变值对象
///
/// 内部容器按约定不可变：
///   - 引擎所有 mutator 都返回 copyWith 后的新 GameState
///   - 不暴露能修改容器的接口
///   - 测试和业务代码不要直接 .add() 或 [idx] = x
class GameState {
  /// 81 个格子的邻接表（Swift gameNears）
  /// adjacency[i] = 与 i 直接相通的 cellId 集合
  final List<Set<int>> adjacency;

  /// 289 个墙壁单元的占用标志（Swift gameWalls）
  final List<bool> wallGrid;

  /// 棋子位置（cellId = x + y*9, 0..80）
  final int topPlayerId;
  final int bottomPlayerId;

  /// 当前回合是上方玩家
  final bool currentPlayerIsTop;

  /// 已放置墙壁数（≤ wallCountPerPlayer）
  final int topWallsPlaced;
  final int bottomWallsPlaced;

  /// 棋谱栈（Swift gameStack；本轮仅记录、不实现 undo）
  final List<MoveRecord> history;

  /// 游戏状态
  final GameStatus status;

  /// 当前玩家可走到的格子（含跳跃；UI 提示用）
  /// 在 switchTurn 时重算并缓存
  final Set<int> validMoves;

  const GameState({...});

  GameState copyWith({...});

  Map<String, dynamic> toJson();
  factory GameState.fromJson(Map<String, dynamic> json);

  // 注：所有构造逻辑（initialize、fromBoardSpec、邻接表构建）
  //     集中在 QuoridorEngine，避免 model 反向依赖 engine
}
```

#### 关键设计点

- **GameState 是纯值对象**：构造、`copyWith`、`toJson/fromJson` 之外的逻辑（包括初始化邻接表、计算 validMoves）全在 engine。这样 model 不依赖 engine，layering 清爽。
- **构造入口在 engine**：用 `QuoridorEngine.initialize()` 或 `QuoridorEngine.fromBoardSpec()` 创建初始 state。
- **先手固定 top**：Swift `arcFirstPlayer()` 用 `arc4random()`，单测不可复现。需要随机时由 lobby 层做随机后传入。
- **`validMoves` 缓存在 state**：避免 UI 每帧重算；`switchTurn` 时刷新。
- **`history` 本轮只追加**：toJson 序列化它，为下轮 LAN 同步预留。

### 5.2 `MoveRecord`（同文件内）

```dart
/// 棋谱栈记录（Swift DataModel）
/// 同时表示「棋子移动」和「墙壁放置」
class MoveRecord {
  final int x;
  final int y;
  final bool isWall;
  final WallOrientation? orientation;  // 仅 isWall=true 时有值
  final bool isTopPlayer;

  const MoveRecord({...});

  factory MoveRecord.move({
    required int cellId,
    required bool isTopPlayer,
  });

  factory MoveRecord.wall({
    required int x,
    required int y,
    required WallOrientation orientation,
    required bool isTopPlayer,
  });

  Map<String, dynamic> toJson();
  factory MoveRecord.fromJson(Map<String, dynamic> json);
}
```

**为什么用 `WallOrientation?` 替代 Swift 的 `h: bool`**：枚举更清晰，null 自然表示走棋记录。

### 5.3 `GameEvent`（`models/game_event.dart`）

```dart
sealed class GameEvent {
  const GameEvent();
}

class PieceMovedEvent extends GameEvent {
  final int fromCellId;
  final int toCellId;
  final bool isTopPlayer;
  const PieceMovedEvent({...});
}

class WallPlacedEvent extends GameEvent {
  final int x;
  final int y;
  final WallOrientation orientation;
  final bool isTopPlayer;
  const WallPlacedEvent({...});
}

class GameOverEvent extends GameEvent {
  final GameStatus status;  // topWin / bottomWin / draw
  const GameOverEvent({required this.status});
}
```

**`sealed class`**：Dart 3 特性，配合 `switch` exhaustive 检查，UI 层处理事件时不会漏分支。

---

## 6. BFS 寻路器

文件：`lib/core/surround_game/engine/bfs_pathfinder.dart`

```dart
/// BFS 寻路器 — 纯函数静态类
///
/// 职责：
///   1. 给定邻接表和起点，找最短路径到对方底线
///   2. 判定路径存在性（墙壁合法性的核心条件）
///
/// Swift 对应：GameAi.swift:226-266 pathForPlayer
///
/// 算法：标准 BFS + 父指针回溯
///   - 队列存 (cellId, parentIndex)
///   - 已访问标记用 List<bool>（避免 Set<int> 的 hash 开销）
///   - 找到第一个满足"到达对方底线"的节点 → 回溯链
///
/// 性能：9×9 棋盘最坏 81 节点 + 平均度数 ≤ 4，单次 BFS < 0.1ms
class BfsPathfinder {
  BfsPathfinder._();

  /// 找从 start 到对方底线的最短路径
  /// 返回路径（含 start 和终点）；不可达返回空列表
  static List<int> findShortestPath(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  );

  /// 路径存在性（findShortestPath 的轻量封装）
  static bool hasPathToGoal(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  );

  /// 双方都能到达自己的终点（墙壁合法性校验的核心判定）
  /// Swift 参考：GameModel.swift:61-78 iWallIsAllow
  static bool bothPlayersHavePath(
    List<Set<int>> adjacency,
    int topPlayerId,
    int bottomPlayerId,
  );
}
```

---

## 7. 游戏引擎

文件：`lib/core/surround_game/engine/game_engine.dart`

```dart
/// QuoridorEngine — 全静态、纯函数
///
/// 职责：
///   1. 初始化棋盘（邻接表 + 墙壁数组 + 棋子起点）
///   2. 走棋（含跳跃规则）
///   3. 放墙（含合法性校验）
///   4. 邻接表更新（墙壁切断格子间连接）
///   5. 胜负判定
///   6. 换手（重算 validMoves）
///
/// Swift 对应：
///   GameModel.swift + GameModel+Action.swift + GameModel+Logic.swift
///
/// 设计约束：
///   - 不持有状态，所有方法形如 (state, args) -> newState
///   - 失败用 null（如非法放墙）— 不抛异常，方便业务逻辑短路
///   - 墙壁校验的"试探"通过深拷贝 adjacency 实现（O(81) 拷贝，可接受）
class QuoridorEngine {
  QuoridorEngine._();

  // ─── 初始化 ───

  /// 创建初始 GameState（top 在 cellId=4，bottom 在 cellId=76，先手固定 top）
  /// Swift 参考：GameModel.swift:161-173 initModelData
  static GameState initialize();

  /// 测试用工厂：从扁平参数构造特定局面（含 placedWalls 列表）
  /// 内部依次调用 buildInitialAdjacency → applyWallToAdjacency
  static GameState fromBoardSpec({
    required int topPlayerId,
    required int bottomPlayerId,
    required bool currentPlayerIsTop,
    List<({int x, int y, WallOrientation o})> placedWalls = const [],
    int topWallsPlaced = 0,
    int bottomWallsPlaced = 0,
  });

  /// 构建初始 81 长度邻接表（标准四连通）
  /// Swift 参考：GameModel.swift:186-202 initGameNearsAndWalls
  static List<Set<int>> buildInitialAdjacency();

  // ─── 走棋 ───
  static GameState? movePiece(GameState state, int targetCellId);

  /// 跳跃规则（Swift scopeForPlayer）：
  ///   邻接 = 对手位置 → 把对手的邻接也加入（直跳）
  ///   不实现官方斜跳（与"Swift 忠实移植"决策一致）
  static Set<int> getValidMoves(
    List<Set<int>> adjacency,
    int playerId,
    int opponentId,
  );

  // ─── 放墙 ───
  static GameState? placeWall(
    GameState state, int x, int y, WallOrientation orientation,
  );

  /// 三道关：
  ///   1. (x, y) 在 [0, 7] 范围内（墙壁占 2 格，所以最大点为 7）
  ///      注：Swift 的 `< 9` 是潜在 bug（x=8 horizontal 会让 wallId+17 越界），
  ///          此处主动修正为 `< 8`，与官方 Quoridor 规则一致。
  ///   2. 拟占用的 3 个 wall 单元未被先前墙壁占用
  ///   3. 试探切断后，双方仍有路径到自己终点
  static bool isWallPlacementValid(
    List<bool> wallGrid,
    List<Set<int>> adjacency,
    int topPlayerId, int bottomPlayerId,
    int x, int y, WallOrientation orientation,
  );

  // ─── 邻接表 / 墙壁 ID ───

  /// 墙壁基址 ID（在 17×17 wallGrid 中的中心位置）
  /// 公式：wallId = (x*2+1) + (y*2+1)*17
  /// Swift 参考：DataModel.swift:82-94
  static int wallBaseId(int x, int y);

  /// 墙壁占用的 3 个 wall 单元
  /// 横向：[baseId-17, baseId, baseId+17]
  /// 竖向：[baseId-1, baseId, baseId+1]
  static List<int> wallOccupiedCells(
    int x, int y, WallOrientation orientation,
  );

  /// 更新邻接表（切断或恢复 2 对相邻格子）
  /// 返回新的 adjacency（深拷贝）；不修改入参
  ///
  /// 横向墙 (h=true)，其中 baseId = x + y*9：
  ///   切断 (baseId, baseId+9) 与 (baseId+1, baseId+10)
  /// 竖向墙 (h=false)：
  ///   切断 (baseId, baseId+1) 与 (baseId+9, baseId+10)
  ///
  /// Swift 参考：GameModel+Action.swift:23-52 removeNearLink / addNearLink
  static List<Set<int>> applyWallToAdjacency(
    List<Set<int>> adjacency,
    int x, int y,
    WallOrientation orientation,
    bool isPlacing,  // true=切断, false=恢复
  );

  // ─── 胜负 ───

  /// 规则（Swift 忠实移植）：
  ///   - topId 到达 y=8 → topWin（除非对方还剩 1 步路 = 平局）
  ///   - bottomId 到达 y=0 → bottomWin（同上）
  ///   - 否则 → running
  ///
  /// Swift 参考：GameModel.swift:123-139 status
  static GameStatus checkStatus(
    List<Set<int>> adjacency,
    int topPlayerId, int bottomPlayerId,
  );

  // ─── 换手 ───

  /// 切换回合
  /// - 翻转 currentPlayerIsTop
  /// - 重算 validMoves
  /// - 重算 status
  ///
  /// 不在 movePiece/placeWall 里自动换手是为了：
  ///   1. 让单测能分别验证"动作"与"换手"
  ///   2. 让网络层有机会在换手前广播状态
  static GameState switchTurn(GameState state);
}
```

---

## 8. 单测计划

### 8.1 组织约定

- 测试框架：`package:test`（不依赖 `flutter_test`，引擎不依赖 Widget）
- 路径：`test/core/surround_game/`（per-unit 一一对应）
- 命令：`flutter test test/core/surround_game/`
- 命名：中文 test 名，每条 `expect` 配 `reason:`，方法粒度用 `group` 嵌套

### 8.2 用例清单（42 用例）

#### `bfs_pathfinder_test.dart`（10）

| # | 用例 | 期望 |
|---|------|------|
| 1 | 空棋盘 top 在 (4,0) 找路 | 长度 9（直走 8 步） |
| 2 | 空棋盘 bottom 在 (4,8) 找路 | 长度 9 |
| 3 | top 已在 y=8（cellId=76） | 长度 1，只含起点 |
| 4 | 全墙隔断（y=4 全行横墙） | 返回空 |
| 5 | 单道横墙在 y=4 但仍能绕 | 长度 > 9 且非空 |
| 6 | `hasPathToGoal` 空棋盘 | true |
| 7 | `hasPathToGoal` 全隔断 | false |
| 8 | `bothPlayersHavePath` 空棋盘 | true |
| 9 | `bothPlayersHavePath` 只阻断 top | false |
| 10 | `bothPlayersHavePath` 只阻断 bottom | false |

#### `game_engine_test.dart`（26）

**初始化与基础（4）**
1. `QuoridorEngine.initialize()` → top=4, bottom=76, status=running, currentPlayerIsTop=true
2. `buildInitialAdjacency()` → 角点度数 2、边格 3、中心格 4
3. `wallBaseId(0,0) = 18`, `wallBaseId(7,7) = 270`
4. `wallOccupiedCells(3,4,horizontal)` 含 3 个连续位置 `[baseId-17, baseId, baseId+17]`

**走棋（4）**
5. top 向下走 (cellId=4 → 13) → topPlayerId 更新
6. top 走到不在 validMoves 的格子 → 返回 null
7. 走棋后 history 长度 +1，最后一条 `isWall=false`
8. 走棋后**不**自动换手（currentPlayerIsTop 不变）

**跳跃（2）**
9. top (4,3), bottom (4,4)：top 的 validMoves 含 (4,5)（跳过 bottom）
10. top (4,3), bottom 不相邻：validMoves 只有四邻接

**放墙（7）**
11. 空棋盘横墙放 (3,4) → 合法；wallGrid 3 单元变 true；adjacency 切断 2 对
12. 同位置再放 → 重叠不合法
13. 横墙叉竖墙（共享中心）→ 不合法
14. 把 top 完全封死（4 块横墙：(0,0)(2,0)(4,0)(6,0)）→ `isWallPlacementValid` false
15. 放墙后 `topWallsPlaced` +1
16. `wallCountPerPlayer` 用尽后再放 → 返回 null
16b. 坐标越界 `placeWall(state, 8, 0, horizontal)` → 返回 null（修正 Swift 的 bug）

**胜负（4）**
17. top 走到 y=8 → checkStatus = topWin
18. bottom 走到 y=0 → checkStatus = bottomWin
19. top 到 y=8 且 bottom 路径长度 = 1 → draw
20. 普通状态 → running

**换手与邻接细节（5）**
21. switchTurn 翻转 currentPlayerIsTop 并重算 validMoves
22. switchTurn 不修改棋子位置和墙壁
23. 横墙 (0,0) → 切断 (0, 9) 和 (1, 10)
24. 竖墙 (0,0) → 切断 (0, 1) 和 (9, 10)
25. `applyWallToAdjacency(..., isPlacing=false)` 完美还原原邻接

#### `game_state_test.dart`（6）

26. GameState 构造 → 全字段断言
27. `copyWith` 单字段修改不影响其它字段
28. `toJson → fromJson` 往返一致（含 history、validMoves）
29. `QuoridorEngine.fromBoardSpec` 构造测试局面，adjacency 与 wallGrid 一致
30. `MoveRecord.move` / `MoveRecord.wall` 工厂字段正确
31. `MoveRecord toJson/fromJson` 往返

### 8.3 测试代码示例

```dart
group('BfsPathfinder', () {
  group('findShortestPath', () {
    test('空棋盘 top 起手 → 长度 9 (8 步直走)', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 4, true);
      expect(path.length, 9, reason: '空棋盘直走 8 步含起点共 9 节点');
      expect(path.first, 4);
      expect(path.last >= 72, true, reason: '终点必在 y=8 行');
    });

    test('top 已在 y=8 → 长度 1', () { /* ... */ });
    test('全隔断 → 空列表', () { /* ... */ });
  });
});
```

### 8.4 测试 fixtures（可选）

如果某些局面构造重复出现，提取到 `test/core/surround_game/_fixtures.dart`：

```dart
/// top 即将到达底线、bottom 路径长度 = 1（draw 边界）
GameState almostDrawState() { /* ... */ }

/// 横墙在 (3,4) 的标准局面
GameState wallAt34Horizontal() { /* ... */ }
```

---

## 9. 执行计划

每阶段一个 atomic commit、`flutter analyze` 0 error、对应单测全绿。

```
┌─────────────────────────────────────────────────────┐
│ P0  整理 _legacy/                  ~20min  │ commit │
│ P1  常量 + 枚举                    ~20min  │ commit │
│ P2  GameState + MoveRecord + event ~40min  │ commit │
│ P3  BFS pathfinder + 测试          ~60min  │ commit │
│ P4a QuoridorEngine 走棋+跳跃+换手  ~60min  │ commit │
│ P4b QuoridorEngine 放墙+胜负       ~60min  │ commit │
│ P5  Service / Lobby noop 收尾      ~30min  │ commit │
│ P6  验证 + 文档                    ~20min  │ commit │
└─────────────────────────────────────────────────────┘
总计 ~5 小时 / 8 commit
```

### P0 — 整理 `_legacy/`（~20min）

1. `git mv` 旧文件到 `lib/core/surround_game/_legacy/`：
   - `pages/game_board_page.dart`
   - `widgets/game_board_widget.dart`、`widgets/direction_pad.dart`
   - `engine/collision_detector.dart`、`engine/game_engine.dart`
   - `models/game_state.dart`、`models/game_event.dart`
2. 修改 `_legacy/` 内文件的相对 import
3. 新建 `_legacy/README.md` 说明删除时机（下轮 UI 完成）
4. `surround_game.dart` 暂时只导出：`models/game_room.dart` + `models/player_input.dart` + `surround_game_constants.dart`
5. `pages/game_lobby_page.dart`、`pages/game_room_page.dart`：跳转 `GameBoardPage` 的地方改为 `PlaceholderPage("Quoridor 重写中")`
6. `surround_game_service.dart`：删除 `executeMove` 方法
7. `flutter analyze` → 0 error
8. **commit**: `chore(surround_game): 旧 UI/engine 暂存到 _legacy/，准备 Quoridor 重写`

**验证**：app 编译启动，进入"围追堵截"大厅能看到 PlaceholderPage。

### P1 — 常量 + 枚举（~20min）

1. 重写 `surround_game_constants.dart`（按 §4）
2. 顶部注释：`Runing → running` 拼写偏差、cellId 编码方式
3. `flutter analyze` → 0 error
4. **commit**: `feat(surround_game): 重写常量与 Quoridor 枚举（boardSize=9, wallGrid=17）`

### P2 — GameState + MoveRecord + event（~40min）

1. 重写 `models/game_state.dart`（按 §5.1、§5.2）
   - `GameState` 类、`const` 构造、`copyWith`、`toJson/fromJson`
   - `MoveRecord` + `MoveRecord.move` / `MoveRecord.wall` 工厂 + `toJson/fromJson`
   - **不包含** initialize/fromBoardSpec/buildInitialAdjacency（这些在 P4a 跟随 engine 一起出现）
2. 重写 `models/game_event.dart`（按 §5.3）
3. 新建 `test/core/surround_game/game_state_test.dart`（用例 26-28 + 30-31 = 5 个；29 留到 P4a 一起加）
4. `flutter test test/core/surround_game/game_state_test.dart` → 全绿
5. `flutter analyze` → 0 error
6. **commit**: `feat(surround_game): GameState + MoveRecord + GameEvent (含单测 5 用例)`

### P3 — BFS pathfinder + 测试（~60min）

1. 新建 `engine/bfs_pathfinder.dart`（按 §6）
2. 新建 `test/core/surround_game/bfs_pathfinder_test.dart`（10 用例）
3. `flutter test test/core/surround_game/bfs_pathfinder_test.dart` → 全绿
4. `flutter analyze` → 0 error
5. **commit**: `feat(surround_game): BFS pathfinder (含单测 10 用例)`

### P4a — QuoridorEngine 走棋 + 跳跃 + 换手（~60min）

1. 新建 `engine/game_engine.dart`，先实现：
   - `initialize` / `fromBoardSpec` / `buildInitialAdjacency`
   - `wallBaseId` / `wallOccupiedCells` / `applyWallToAdjacency`
   - `movePiece` / `getValidMoves`（含跳跃）
   - `switchTurn`
2. 新建 `test/core/surround_game/game_engine_test.dart`，写：初始化(1-4) + 走棋(5-8) + 跳跃(9-10) + 邻接(23-25) + 换手(21-22) = 15 用例
3. 补 `game_state_test.dart` 用例 29（`fromBoardSpec` 构造测试局面）
4. `flutter test` 累计 31 用例全绿（state 5 + BFS 10 + engine 15 + state 1）
5. `flutter analyze` → 0 error
6. **commit**: `feat(surround_game): QuoridorEngine 走棋+跳跃+换手 (单测 16 用例)`

### P4b — QuoridorEngine 放墙 + 胜负（~60min）

1. 添加：`placeWall` / `isWallPlacementValid` / `checkStatus`
2. 测试增量：放墙(11-16, 16b) + 胜负(17-20) = 11 用例
3. `flutter test` 累计 42 用例全绿
4. `flutter analyze` → 0 error
5. **commit**: `feat(surround_game): QuoridorEngine 放墙+胜负 (单测 11 用例)`

### P5 — Service / Lobby noop 收尾（~30min）

1. `surround_game_service.dart`：
   - `_handleGameSync`、`_handleGameInput` 改为 200 OK + log "noop"
   - 删除 `currentGameState` 字段（不再有意义）
2. `surround_game.dart` 更新导出：
   ```dart
   export 'surround_game_constants.dart';
   export 'models/game_room.dart';
   export 'models/player_input.dart';
   export 'models/game_state.dart';
   export 'models/game_event.dart';
   export 'engine/bfs_pathfinder.dart';
   export 'engine/game_engine.dart';
   ```
3. `flutter analyze` → 0 error
4. `flutter test test/core/surround_game/` → 全 42 用例绿（BFS 10 + engine 26 + state 6）
5. **commit**: `chore(surround_game): Service 收尾 + 导出对齐`

### P6 — 验证 + 文档（~20min）

1. 启动 app 确认：
   - 围追堵截大厅能进
   - 创建房间 → 看到 PlaceholderPage
   - UDP 多设备发现仍工作
2. 在 `docs/围追堵截-Quoridor任务清单.md` 顶部追加完成标记
3. 在 `docs/围追堵截-Quoridor重写执行文档.md` 标记本轮章节
4. **commit**: `docs(surround_game): Phase 1 引擎完成标记`

---

## 10. 风险与回退

| 风险 | 应对 |
|------|------|
| Swift `removeNearLink` 索引计算错（off-by-one）| 测试 23/24 直接断言切断的两对格子 |
| `isWallPlacementValid` 试探 BFS 性能 | 9×9 棋盘 BFS < 0.1ms，10 块墙 × 几次试探无压力 |
| `_legacy/` 内文件相互引用断了 | P0 单独提交，分支保留旧版可 revert 单 commit |
| 序列化字段顺序变 | toJson/fromJson 往返单测兜底 |
| 双 emulator UDP 发现回归 | P6 必走 |
| `arc4random` → 固定 top 先手对体验的影响 | UI 层后续可在 lobby 加一次随机；引擎只关心可复现 |

---

## 11. 不在本轮范围

显式排除（避免范围漂移）：

- ❌ UI 重写（`GameBoardWidget` 9×9 CustomPaint、墙壁拖拽 UX、`game_board_page.dart` 回合控制）
- ❌ Service 层重构（`executeAction` 接口、回合制 LAN 同步协议、PlayerInput 改造）
- ❌ AI 玩家（含 `findAllPaths`、`AiPlayer.chooseAction`）
- ❌ 悔棋 / `iRetractGame`
- ❌ 官方斜跳规则（对手后方有墙时跳到左右）
- ❌ 随机先手（`arc4random` 等价）

下一轮（"Quoridor UI 重写"）会重新设计、独立成 spec。

---

## 12. 参考索引

| Quoridor-ios 文件 | 关键行 | 对应功能 |
|------------------|-------|---------|
| `DataModel.swift:77-94` | id / wallIds | 双网格编址 |
| `GameModel.swift:9-18` | iPutWall | 墙壁放置 |
| `GameModel.swift:21-28` | iMove | 棋子移动 |
| `GameModel.swift:61-78` | iWallIsAllow | 墙壁合法性 |
| `GameModel.swift:117-120` | player 属性 | 换手判定 |
| `GameModel.swift:123-139` | status | 胜负判定 |
| `GameModel.swift:186-202` | initGameNearsAndWalls | 邻接表初始化 |
| `GameModel+Action.swift:23-52` | removeNearLink | 邻接表更新 |
| `GameModel+Logic.swift:6-20` | scopeForPlayer | 跳跃规则 |
| `GameAi.swift:226-266` | pathForPlayer | BFS 寻路 |
