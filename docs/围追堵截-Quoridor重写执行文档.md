# 围追堵截 (Quoridor) 重写执行文档

> 实施状态：Phase 1（引擎层）已全部完成（44 单测通过）。见 `docs/superpowers/specs/2026-06-12-quoridor-engine-rewrite-design.md`。

> 严格参考 `.claude/repo/Quoridor-ios`（Swift 实现），适配当前项目已有的
> Flutter 设计模式（`word_drag` 的 Provider/Notifier、`localnet` 的单例工厂、`snake_game`/`game_2048` 的网格渲染）。
> **只改 `lib/core/surround_game/` 内部**，不涉及 `localnet`。

---

## 1. 核心差异：当前实现 vs Quoridor

| 维度 | ❌ 当前实现 | ✅ 目标 Quoridor |
|------|-----------|----------------|
| 棋盘 | 20×15 带边界 | **9×9** 无边障 |
| 网格系统 | 单层 | **双网格**：9×9 棋子 + 17×17 墙壁 |
| 回合制 | 双方同时走 | **轮流**，每回合走棋或放墙 |
| 动作 | 只能走棋 | **二选一**：走 1 步 **或** 放 1 面墙 |
| 墙壁 | 无 | 每人 **10 块** |
| 轨迹 | 留下轨迹不可穿越 | **无轨迹**，墙壁替代 |
| 跳跃 | 无 | 两棋相邻时 **跳过对方** |
| 胜利 | 把对方逼入死角 | **先到对方底线** |
| 寻路 | 无 | **BFS 最短路径**（路径验证 + AI） |
| 网络 | HTTP 联机 | 保留，同上 |

---

## 2. 文件目录设计

遵循当前项目的 b 方案（`core/` 模块 + `lab/demos/` 桥接）。

### 新增/修改文件清单

```
lib/core/surround_game/
├── surround_game.dart                        # 导出入口（修改）
├── surround_game_constants.dart               # 常量（大改）
├── surround_game_service.dart                 # 保留（不改动网络部分）
├── models/
│   ├── game_room.dart                         # 保留（不改）
│   ├── game_state.dart                        # 全改 → QuoridorState
│   ├── player_input.dart                      # 保留（不改）
│   └── game_event.dart                        # 全改 → QuoridorEvent
├── engine/
│   ├── collision_detector.dart                # 删除（不再需要）
│   ├── game_engine.dart                       # 全改 → QuoridorEngine
│   └── bfs_pathfinder.dart                    # ★ 新增：BFS 寻路核心
├── pages/
│   ├── game_lobby_page.dart                   # 保留（不改）
│   ├── game_room_page.dart                    # 保留（不改）
│   └── game_board_page.dart                   # 全改
└── widgets/
    ├── game_board_widget.dart                 # 全改 → 9×9 网格
    └── direction_pad.dart                     # 保留（不改）
```

### 文件名映射（Swift → Dart）

| Quoridor-ios (Swift) | surround_game (Dart) | 说明 |
|---------------------|---------------------|------|
| `DataModel.swift` | `models/game_state.dart` | 合并到 GameState |
| `GameModel.swift` | — | State + Engine 替代 |
| `GameModel+Action.swift` | `engine/game_engine.dart` | 并入 Engine |
| `GameModel+Logic.swift` | `engine/game_engine.dart` | 并入 Engine |
| `GameAi.swift` | `engine/bfs_pathfinder.dart` | BFS 寻路 |
| `GameController.swift` | `pages/game_board_page.dart` | UI 控制器 |
| `ChessBoard.swift` | `widgets/game_board_widget.dart` | 棋盘渲染 |
| `FrameCalculator.swift` | `widgets/game_board_widget.dart` | 坐标计算 |
| `ChessPlayer.swift` | `widgets/game_board_widget.dart` | 棋子渲染 |
| `ChessWall.swift` | `widgets/game_board_widget.dart` | 墙壁渲染 |
| `PlayerPrompt.swift` | `widgets/game_board_widget.dart` | 可移动提示 |
| `WallPrompt.swift` | `widgets/game_board_widget.dart` | 墙壁预览 |
| `TurnManager` (Swift 无，概念) | `pages/game_board_page.dart` | 回合控制 |

---

## 3. 数据模型设计

### 3.1 常量 (`surround_game_constants.dart`)

```dart
class SurroundGameConstants {
  // 棋盘
  static const int boardSize = 9;              // 9×9 棋子网格
  static const int wallGridSize = 17;           // 17×17 墙壁网格
  static const int wallCountPerPlayer = 10;      // 每人 10 块挡板

  // 起始位置（和 Quoridor-ios 一致：GameModel.swift:163-164）
  // DataModel(x: 4, y: 0, h: true, t: false)  topPlayer
  // DataModel(x: 4, y: 8, h: false, t: false) downPlayer
  static const int playerTopStart = 4;   // x=4
  static const int playerTopRow = 0;     // y=0
  static const int playerBottomStart = 4;
  static const int playerBottomRow = 8;

  // 终点判定（GameAi.swift:407-413）
  // topEnd: data > 71
  // downEnd: data < 9
  static const int maxCellId = 80;        // 8*9+8
  static const int topEndThreshold = 71;
  static const int downEndThreshold = 9;

  // 墙壁 ID 计算（DataModel.swift:86-93）
  // wallId = (x*2+1) + (y*2+1)*17
  static const int wallGridColumns = 17;
}
```

### 3.2 枚举

```dart
/// 参考 DataModel.swift — h 和 t 属性
/// h: true=horizontal(墙) / top(棋), false=vertical(墙) / down(棋)
/// t: true=wall, false=piece

enum CellType { empty, playerTop, playerBottom }

enum WallOrientation { horizontal, vertical }

enum TurnAction { move, placeWall }  // 玩家当前回合选择

enum GameStatus { runing, topWin, downWin, draw }

/// 格子状态（用于 9×9 棋盘渲染）
/// 参考 ChessBoard.swift draw rect 逻辑
enum CellState {
  empty,
  playerTop,      // 上方棋子所在格
  playerBottom,   // 下方棋子所在格
  validMove,      // 可移动高亮（参考 PlayerPrompt.swift）
  invalidWall,    // 墙壁不可放置（参考 WallPrompt.swift 红色）
}
```

### 3.3 GameState (替换现有 game_state.dart)

参考 `GameModel.swift` + `DataModel.swift`：

```dart
class GameState {
  // 棋盘数据 — 邻接表（GameModel.swift:142 gameNears）
  // 81 个格子，每个维护可通行的邻接格子列表
  final List<Set<int>> adjacency;

  // 墙壁数据 — 17×17 布尔数组（GameModel.swift:145 gameWalls）
  final List<bool> wallGrid;

  // 棋子（DataModel 核心字段）
  final int topPlayerId;    // id = x + y*9, 0-80
  final int bottomPlayerId;
  final bool currentPlayerIsTop;  // true=上, false=下

  // 墙壁计数
  final int topWallsPlaced;     // 已放置数
  final int bottomWallsPlaced;

  // 回合历史（GameModel.swift:113 gameStack）
  final List<MoveRecord> history;

  // 游戏状态
  final GameStatus status;

  // 动画/提示状态
  final Set<int> validMoves;    // 当前玩家可移动的格子
  final bool isPlacingWall;     // 是否在放置墙壁模式

  // 初始化
  factory GameState.initialize();
}
```

### 3.4 MoveRecord (走棋记录)

```dart
/// 对应 DataModel — 同时表示棋子移动和墙壁放置
class MoveRecord {
  final int x;             // 0-8
  final int y;             // 0-8
  final bool isWall;       // t: true=wall, false=piece
  final bool orientation;  // h: true=horizontal, false=vertical (仅 wall)
  // 玩家标识
  final bool isTopPlayer;
}
```

---

## 4. 引擎层设计

### 4.1 BFS 寻路器（新增 `bfs_pathfinder.dart`）

参考 `GameAi.swift:226-266`：

```dart
class BfsPathfinder {
  /// BFS 最短路径（GameAi.swift pathForPlayer）
  /// 返回从 start 到终点（topEnd/downEnd）的最短格子 ID 数组
  /// 无路径时返回 []
  static List<int> findShortestPath(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  );

  /// 检查是否至少存在一条路径（GameModel.swift iWallIsAllow）
  static bool hasPathToGoal(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  );

  /// 检查双方都有路径（墙壁放置合法性核心条件）
  static bool bothPlayersHavePath(
    List<Set<int>> adjacency,
    int topId,
    int bottomId,
  );

  /// 全路径分析（GameAi.swift allPathForPlayer）
  /// 递归探索所有可能路径（用于 AI 策略）
  static List<List<int>> findAllPaths(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  );
}
```

### 4.2 游戏引擎（`game_engine.dart`，替换现有）

参考 `GameModel.swift` + `GameModel+Action.swift` + `GameModel+Logic.swift`：

```dart
class QuoridorEngine {
  /// 初始化新游戏（GameModel.swift:161-173 initModelData）
  static GameState initialize();

  /// 移动棋子（GameModel.swift:21-28 iMove）
  /// 返回新状态，包含 validMoves 更新
  static GameState movePiece(GameState state, int targetCellId);

  /// 放置墙壁（GameModel.swift:9-18 iPutWall）
  /// 先校验 iWallIsAllow，失败返回 null
  static GameState? placeWall(
    GameState state,
    int x, int y, WallOrientation orientation
  );

  /// 墙壁合法性验证（GameModel.swift:61-78 iWallIsAllow）
  /// 1. 坐标在 0-8
  /// 2. 不与现有墙重叠
  /// 3. 双方都有路径到终点
  static bool isWallPlacementValid(
    List<bool> wallGrid,
    List<Set<int>> adjacency,
    int topId, int bottomId,
    int x, int y, WallOrientation orientation
  );

  /// 获取当前玩家可移动范围（GameModel+Logic.swift:6-20 scopeForPlayer）
  /// 含跳跃规则
  static Set<int> getValidMoves(
    List<Set<int>> adjacency,
    int playerId, int opponentId
  );

  /// 更新邻接表（GameModel+Action.swift:23-52 removeNearLink）
  /// 放置墙壁后切断格子和连接
  static List<Set<int>> applyWallToAdjacency(
    List<Set<int>> adjacency,
    int x, int y, WallOrientation orientation,
    bool isPlacing  // true=放置, false=移除
  );

  /// 墙壁 ID 计算（DataModel.swift:82-94）
  /// wallId = (x*2+1) + (y*2+1)*17
  static int wallBaseId(int x, int y);

  /// 墙壁在 17×17 网格占用的 3 个格子（DataModel.swift wallIds）
  static List<int> wallOccupiedCells(int x, int y, WallOrientation orientation);

  /// 检查游戏是否结束（GameModel.swift:123-139 status）
  static GameStatus checkStatus(int topId, int bottomId);

  /// 换手（GameController.swift:69-88 changePlayer）
  /// 切换 currentPlayerIsTop + 重新计算 validMoves
  static GameState switchTurn(GameState state);
}
```

### 4.3 墙壁放置细节（Quoridor-ios 核心机制）

```
17×17 墙壁网格映射：

单元格编号 0-288
横向墙壁 (h=true, 占同一行三列):
  wallId = baseId + 17
  wallId = baseId
  wallId = baseId - 17

竖向墙壁 (h=false, 占同一列三行):
  wallId = baseId + 1
  wallId = baseId
  wallId = baseId - 1

其中 baseId = (x*2+1) + (y*2+1)*17

邻接切断 (GameModel+Action.swift:23-52):
  横向 (h=true):
    - 切断 (id, id+9) 之间的连接
    - 切断 (id+1, id+10) 之间的连接
  竖向 (h=false):
    - 切断 (id, id+1) 之间的连接
    - 切断 (id+9, id+10) 之间的连接
```

---

## 5. UI 层设计

### 5.1 棋盘 Widget（`game_board_widget.dart`，全改）

参考 `ChessBoard.swift` + `ChessPlayer.swift` + `ChessWall.swift` + `PlayerPrompt.swift` + `WallPrompt.swift`：

```dart
class GameBoardWidget extends StatelessWidget {
  final GameState state;
  final void Function(int cellId)? onCellTap;     // 走棋点击
  final void Function(int x, int y, WallOrientation)? onWallPlace;  // 放墙

  // 渲染层次（从下到上）：
  // 1. 9×9 网格背景（ChessBoard）
  // 2. 墙壁线（ChessWall）— 画在格子之间的缝隙
  // 3. 可移动高亮（PlayerPrompt）— validMoves 高亮
  // 4. 棋子（ChessPlayer）— 两个圆形标记
  // 5. 墙壁预览（WallPrompt）— 拖拽时的半透明
}
```

**渲染方式**：使用 `CustomPaint` + `Canvas`（对应 Swift 的 Core Graphics `drawRect:`）：

```dart
class BoardPainter extends CustomPainter {
  // 参数: cellSize, distance, 棋格 ID, 墙壁数据, 玩家位置, validMoves

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 画网格线 (ChessBoard)
    // 2. 画墙壁 (ChessWall)
    // 3. 画可移动提示 (PlayerPrompt)
    // 4. 画棋子 (ChessPlayer)
    // 5. 画墙壁预览 (WallPrompt)
  }
}
```

**坐标计算**（参考 `FrameCalculator.swift`）：

```dart
/// cellSize = (可用宽度) / 11
/// distance = cellSize * 1.25
/// 棋盘起点 offsetX = (可用宽度 - distance * 8) / 2
/// 格子 n 的屏幕位置 = offset + n * distance
```

### 5.2 游戏主页面（`game_board_page.dart`，全改）

参考 `GameController.swift` 的触摸路由逻辑：

```dart
class GameBoardPage extends StatefulWidget {
  // 接收 GameState，管理回合控制
}

class _GameBoardPageState extends State<GameBoardPage> {
  // ─── 状态 ───
  late GameState _state;
  bool _isPlacingWall = false;      // 放墙模式（toggle）
  int? _wallDragX, _wallDragY;      // 拖拽中的墙壁位置
  WallOrientation? _wallOrientation; // 拖拽中的墙壁方向

  // ─── 走棋逻辑（对应 iMove） ───
  void onCellTap(int cellId) {
    if (!_state.validMoves.contains(cellId)) return;
    if (_state.currentPlayerIsTop != _isMyTurn) return;

    _state = QuoridorEngine.movePiece(_state, cellId);
    if (_state.status != GameStatus.runing) { showResult(); return; }
    _state = QuoridorEngine.switchTurn(_state);
  }

  // ─── 放墙逻辑（对应 iPutWall） ───
  void onWallPlace(int x, int y, WallOrientation orientation) {
    final newState = QuoridorEngine.placeWall(
      _state, x, y, orientation,
    );
    if (newState == null) return;  // 不合法
    _state = newState;
    _state = QuoridorEngine.switchTurn(_state);
  }
}
```

### 5.3 回合控制 UI

当前项目已有一个很好的方向键 `DirectionPad`，但 Quoridor 是**点击选择目标格子**（而非方向键连续走）。

```
┌─────────────────────────────────┐
│  步数: 5  │  蓝墙: 7/10         │  ← 顶部信息栏
│  ⬤ P1 (上)                     │  ← 当前轮到谁
├─────────────────────────────────┤
│                                 │
│        9×9 棋盘                 │  ← 可点击格 + 高亮
│        (CustomPaint)            │
│                                 │
├─────────────────────────────────┤
│  [走棋]  [放墙↕] [重来]         │  ← 底部动作栏
│  蓝方移动范围: █ █ █ █         │
└─────────────────────────────────┘
```

- **点击走棋模式**（默认）：棋盘上的可达格子高亮（GREEN 半透明），点击移动
- **放置墙壁模式**（toggle）：点击格子之间的缝隙放置墙壁，预览红色=不合法
- **模式切换**：底部按钮 `[走棋]` `[放墙]`

---

## 6. 与 LocalNet 的集成

**现有 `surround_game_service.dart` 不做大改**，只做两点调整：

```dart
/// 1. executeMove 参数改为支持 Quoridor 两种动作
void executeAction({
  required TurnAction action,
  int? targetCellId,      // 走棋目标
  int? wallX, int? wallY, // 墙壁位置
  WallOrientation? wallOrientation,
});

/// 2. startGame 返回 QuoridorState
void startGame() {
  final state = QuoridorEngine.initialize();
  _currentGameState = state;  // 注意类型兼容
  _gameStateController.add(state);
}
```

**兼容策略**：
- `GameState` 替换为新的 `QuoridorState`，但类名保持 `GameState` 以免破坏导出
- `surround_game_service.dart` 只引用 `engine/game_engine.dart` 和 `models/game_state.dart`，不直接引用引擎细节
- 网络序列化（`toJson/fromJson`）需要更新为新模型

---

## 7. 实施阶段

### Phase 1：数据模型 + 常量（0.5天）

- [ ] `surround_game_constants.dart` — 全部常量重写
- [ ] `models/game_state.dart` — QuoridorState 完整实现
- [ ] `models/game_event.dart` — 更新事件定义
- [ ] `surround_game.dart` — 更新导出

### Phase 2：BFS 引擎（0.5天）

- [ ] `engine/bfs_pathfinder.dart` — BFS 最短路径 + 路径验证 + 全路径分析
- [ ] `engine/game_engine.dart` — QuoridorEngine（初始化/走棋/放墙/校验/换手）

### Phase 3：棋盘 UI（0.5天）

- [ ] `widgets/game_board_widget.dart` — CustomPaint 棋盘 + 墙壁 + 棋子 + 提示
- [ ] `pages/game_board_page.dart` — 回合控制 + 动作模式切换

### Phase 4：集成验证（0.5天）

- [ ] `surround_game_service.dart` — executeAction 适配
- [ ] 本地双人完整流程测试
- [ ] `flutter analyze` + 编译验证

**总计约 2 天。**

---

## 8. 验证标准

| 验收项 | 验收方法 |
|--------|---------|
| 9×9 棋盘正确渲染 | 启动游戏，可见 9×9 网格 + 两个棋子 ± 墙壁 |
| 走棋功能 | 点击高亮格子 → 棋子移动到目标格，正确换手 |
| 墙壁放置 | 切换放墙模式 → 点击格间 → 墙壁出现 |
| 墙壁合法性 | 被墙壁阻挡的隔壁不可走；堵死路径的墙壁不允许放置 |
| 跳跃规则 | 两棋相邻时，可跳过对方到对方后方格子 |
| 胜利判定 | 棋子到达对方底线 → 游戏结束弹窗 |
| 双人手动 | P1 和 P2 轮流操作 |
| `flutter analyze` | 0 error |

---

## 9. 参考文件索引

| Quoridor-ios 文件 | 关键行 | 对应功能 |
|------------------|--------|---------|
| `DataModel.swift:77-94` | id/wallIds | 双网格编址 |
| `GameModel.swift:9-18` | iPutWall | 墙壁放置 |
| `GameModel.swift:21-28` | iMove | 棋子移动 |
| `GameModel.swift:61-78` | iWallIsAllow | 墙壁合法性 |
| `GameModel.swift:117-120` | player 属性 | 换手判定 |
| `GameModel.swift:123-139` | status | 胜负判定 |
| `GameModel+Action.swift:23-52` | removeNearLink | 邻接表更新 |
| `GameModel+Logic.swift:6-20` | scopeForPlayer | 跳跃规则 |
| `GameAi.swift:226-266` | pathForPlayer | BFS 寻路 |
| `GameAi.swift:271-360` | allPathForPlayer | 全路径分析 |
| `FrameCalculator.swift` | — | 坐标计算公式 |

