# 围追堵截 (Quoridor) 重写 — 任务清单

> 严格参考 `.claude/repo/Quoridor-ios`
> **只改 `lib/core/surround_game/` 内部**，不涉及 `localnet`。
> 每完成一个 Task 后 `flutter analyze` 确认零 error。

---

> ## Phase 1 — 引擎重写已完成
>
> | 阶段 | 状态 | Commit |
> |------|------|--------|
> | P0 整理 _legacy/ | Done | `03277ed` |
> | P1 常量+枚举 | Done | `03277ed` |
> | P2 GameState+MoveRecord+Event | Done | `c66e78d` |
> | P3 BFS pathfinder | Done | `07917da` |
> | P4a 引擎走棋+跳跃+换手 | Done | `a63a21c` |
> | P4b 引擎放墙+胜负 | Done | `04acc5a` |
> | P5 Service noop 收尾 | Done | `98d2379` |
> | P6 验证+文档 | Done | — |
>
> **合计 44 单测，全部通过。下轮期待：Quoridor UI 重写。**
>
> ---

## 执行顺序（参考）

```
P0→P1(常量+枚举) → P2(数据模型) → P3(BFS引擎) → P4a(引擎走棋+跳跃+换手) → P4b(引擎放墙+胜负) → P5(Service收尾) → P6(验证+文档)
```

---

## T1 — 重写常量文件

**文件**: `lib/core/surround_game/surround_game_constants.dart`

### 1.1 删除旧常量
- [ ] 删除 `boardRows`(20)、`boardCols`(15)、`hostStartRow`/`hostStartCol`、`clientStartRow`/`clientStartCol`
- [ ] 删除 `winScore`(3)、`kMaxPlayers`(2)、`kGameType`、`kCountdownSeconds`、`kClientTimeoutSeconds`
- [ ] 删除所有 `kPathGame*` 和 `kBroadcast*` 网络常量
- [ ] 删除 `Direction` 枚举（不再需要方向键移动）
- [ ] 删除 `CellState` 旧枚举（`empty/hostTrail/clientTrail/wall`）
- [ ] 删除 `RoomState`、`PlayerId`（保留到 game_room.dart）

### 1.2 新增常量
- [ ] `boardSize = 9`
- [ ] `wallGridSize = 17`
- [ ] `wallCountPerPlayer = 10`
- [ ] 起始位置: `playerTopStart = 4`, `playerTopRow = 0`, `playerBottomStart = 4`, `playerBottomRow = 8`
- [ ] 终点阈值: `maxCellId = 80`, `topEndThreshold = 71`, `downEndThreshold = 9`
- [ ] `wallGridColumns = 17`
- [ ] `wallBaseId` 的计算公式: `(x*2+1) + (y*2+1)*17`

### 1.3 新增枚举
- [ ] `WallOrientation { horizontal, vertical }`
- [ ] `TurnAction { move, placeWall }`
- [ ] `GameStatus { runing, topWin, downWin, draw }`
- [ ] `CellState` 替换为: `empty, playerTop, playerBottom, validMove, invalidWall`

---

## T2 — 重写数据模型

### 2.1 game_state.dart（全改）

**文件**: `lib/core/surround_game/models/game_state.dart`

参考 `GameModel.swift` + `DataModel.swift`：

- [ ] `GameState` 类定义，包含字段：
  - `adjacency: List<Set<int>>` — 81 个邻接表（`GameModel.swift:142`）
  - `wallGrid: List<bool>` — 289 个墙壁布尔数组（`GameModel.swift:145`）
  - `topPlayerId: int` — 0-80 格子编号（`DataModel.swift id`）
  - `bottomPlayerId: int`
  - `currentPlayerIsTop: bool` — 谁是当前回合玩家
  - `topWallsPlaced: int` / `bottomWallsPlaced: int` — 墙壁使用计数
  - `history: List<MoveRecord>` — 棋谱栈（`GameModel.swift:113`）
  - `status: GameStatus` — 游戏状态
  - `validMoves: Set<int>` — 当前可移动范围
  - `isPlacingWall: bool` — 墙壁放置模式标志
- [ ] `factory GameState.initialize()` — 初始化：
  - 构建初始邻接表（81 个格子，标准四连通）
  - 清空 wallGrid（289 个 false）
  - 棋子: top(4,0) bottom(4,8)
  - `topWallsPlaced=0`, `bottomWallsPlaced=0`
  - `history = []`, `status = GameStatus.runing`
  - 计算初始 validMoves
- [ ] `copyWith()` 方法
- [ ] `toJson()` / `fromJson()`（保留网络序列化）

### 2.2 game_event.dart（全改）

**文件**: `lib/core/surround_game/models/game_event.dart`

- [ ] 删除旧事件:
  - `CollisionEvent`, `ScoreEvent`, `ResetRoundEvent`（轨迹系统不再需要）
- [ ] 保留/重命名:
  - `GameOverEvent` — 改用 `winnerId: String`, `isTopWin: bool`
- [ ] 新增事件:
  - `WallPlacedEvent` — 墙壁放置事件（x, y, orientation）
  - `PieceMovedEvent` — 棋子移动事件（fromId, toId）

### 2.3 MoveRecord 模型

**文件**: `lib/core/surround_game/models/game_state.dart`（内部类或同级文件）

- [ ] `MoveRecord` 类：
  - `x, y: int` — 0-8 坐标
  - `isWall: bool` — true=墙, false=棋
  - `orientation: bool` — 仅墙: true=横, false=竖
  - `isTopPlayer: bool` — 哪方操作

---

## T3 — 更新导出入口

**文件**: `lib/core/surround_game/surround_game.dart`

- [ ] 移除 `export 'engine/collision_detector.dart'`
- [ ] 添加 `export 'engine/bfs_pathfinder.dart'`
- [ ] 移除旧的导出（`game_room`、`player_input` 保留）
- [ ] 确保所有新文件被导出

---

## T4 — BFS 寻路引擎

**文件**: `lib/core/surround_game/engine/bfs_pathfinder.dart`（**新增**）

参考 `GameAi.swift`：

- [ ] `findShortestPath(adjacency, start, isTopPlayer)` — BFS 最短路径
  - 维护已访问节点集合和队列
  - `Node(id, parent)` 结构体用于回溯
  - 终点判定: top 看 `id > 71`，bottom 看 `id < 9`
  - 返回 `List<int>`（从 start 到终点的格子 ID 路径）
  - 无路径返回空列表
- [ ] `hasPathToGoal(adjacency, start, isTopPlayer)` — 路径存在性检查
  - 调用 `findShortestPath`，判断返回非空
- [ ] `bothPlayersHavePath(adjacency, topId, bottomId)` — 双方可达
  - 墙壁校验核心：双方都 `hasPathToGoal`
- [ ] `findAllPaths(adjacency, start, isTopPlayer)` — 全路径分析（AI 备选）
  - 递归多分支探索
  - 不阻塞棋盘即可返回单一路径

---

## T5 — 游戏引擎（全改）

**文件**: `lib/core/surround_game/engine/game_engine.dart`

参考 `GameModel.swift` + `GameModel+Action.swift` + `GameModel+Logic.swift`：

### 5.1 初始化
- [ ] `GameEngine.initialize()` — 返回初始 GameState
  - 复用 GameState.initialize()

### 5.2 核心动作
- [ ] `movePiece(state, targetCellId)` — 棋子移动
  - 验证 `targetCellId` 在 `state.validMoves` 中
  - 更新对应棋子位置
  - 记录 `MoveRecord` 到 history
  - 不触发切换——交给 switchTurn

- [ ] `placeWall(state, x, y, orientation)` — 放置墙壁
  - 调用 `isWallPlacementValid` 校验
  - 校验通过：更新 wallGrid，更新 adjacency
  - 记录 MoveRecord，减少墙壁计数
  - 校验失败：返回 null

### 5.3 墙壁校验
- [ ] `isWallPlacementValid(wallGrid, adjacency, topId, bottomId, x, y, orientation)` — 墙壁合法性
  - 坐标 0-8 范围内
  - 墙壁不重叠（wallId 三格都没有被占用）
  - 模拟放置后 `bothPlayersHavePath`
  - ★ 关键：需要暂存 wallGrid 和 adjacency 的修改，验证完再恢复

### 5.4 邻接表操作
- [ ] `applyWallToAdjacency(adjacency, x, y, orientation, isPlacing)` — 更新邻接
  - 横向: 切断 `(id, id+9)` 和 `(id+1, id+10)`
  - 竖向: 切断 `(id, id+1)` 和 `(id+9, id+10)`
  - isPlacing=true=切断, false=恢复

### 5.5 墙壁 ID 计算
- [ ] `wallBaseId(x, y)` — `(x*2+1) + (y*2+1)*17`
- [ ] `wallOccupiedCells(x, y, orientation)` — 返回 3 个 wallId
  - 横向: `[baseId-17, baseId, baseId+17]`
  - 竖向: `[baseId-1, baseId, baseId+1]`

### 5.6 跳跃规则
- [ ] `getValidMoves(adjacency, playerId, opponentId)` — 可移动范围
  - 正常邻接格子
  - 如果邻接格子 = opponentId → 继续查 opponent 的邻接格
    - opponent 后方的格子加入 validMoves
  - 返回 `Set<int>`

### 5.7 游戏状态
- [ ] `checkStatus(topId, bottomId)` — 胜负判定
  - topId > 71 → topWin
  - bottomId < 9 → downWin
  - 否则 → runing
- [ ] `switchTurn(state)` — 换手
  - 翻转 `currentPlayerIsTop`
  - 重新计算 `validMoves`
  - 清空 `isPlacingWall`

---

## T6 — 棋盘 Widget（全改）

**文件**: `lib/core/surround_game/widgets/game_board_widget.dart`

参考 `ChessBoard.swift` + `ChessPlayer.swift` + `ChessWall.swift` + `PlayerPrompt.swift` + `WallPrompt.swift`：

### 6.1 BoardPainter (CustomPainter)
- [ ] 实现 `BoardPainter extends CustomPainter`
  - 参数: `state: GameState`, `cellSize: double`, `distance: double`, `offsetX: double`, `offsetY: double`
  - `paint()` 分层渲染:
    1. **画网格** — 画 9×9 格子线（浅灰色），可加圆角矩形容器
    2. **画墙壁** — 遍历 wallGrid，被占用的格子画深色矩形（宽=cellSize*0.15）
    3. **画可移动提示** — validMoves 的格子画半透明绿色圆
    4. **画棋子** — topPlayer 画蓝色圆，bottomPlayer 画红色圆（半径 cellSize*0.4）
  - 坐标: `offsetX + col * distance`, `offsetY + row * distance`

### 6.2 触摸事件
- [ ] 使用 `GestureDetector` 包裹 BoardPainter 的 `CustomPaint`
  - 点击 → 判断点击在哪个格子上 → 触发 `onCellTap(cellId)`
  - 点击在格子之间的缝隙 → 触发 `onWallPlace(x, y, orientation)`
  - 缝隙判断: 距离距某个格子中心约 `distance/2` 时为缝隙

### 6.3 GameBoardWidget
```dart
class GameBoardWidget extends StatelessWidget {
  final GameState state;
  final void Function(int cellId)? onCellTap;
  final void Function(int x, int y, WallOrientation)? onWallPlace;
}
```

- [ ] LayoutBuilder + 屏幕适配
  - `cellSize = (可用宽度) / 11`
  - `distance = cellSize * 1.25`
  - `offsetX = (可用宽度 - distance * 8) / 2`
  - 棋盘整体宽度 = `distance * 8 + cellSize`

---

## T7 — 游戏主页面（全改）

**文件**: `lib/core/surround_game/pages/game_board_page.dart`

参考 `GameController.swift`：

### 7.1 状态
- [ ] `_state: GameState`
- [ ] `_isPlacingWall: bool` — 模式标志
- [ ] `_currentPlayerIsTop: bool` — 本地双人用（P1 蓝=top, P2 红=bottom）

### 7.2 走棋流程
- [ ] `onCellTap(cellId)`
  - 无效点击（不在 validMoves 中、不在自己回合）→ 忽略
  - 调用 `GameEngine.movePiece(state, cellId)`
  - 如果 `status != runing` → 弹出结果
  - 调用 `GameEngine.switchTurn()`
  - setState 刷新

### 7.3 放墙流程
- [ ] `onWallPlace(x, y, orientation)`
  - 调用 `GameEngine.placeWall(state, x, y, orientation)`
  - 返回 null → 无效操作，忽略
  - 有效 → switchTurn + setState

### 7.4 UI 布局
```
┌─────────────────────────┐
│ 走棋/放墙模式切换  │ 蓝墙 5/10 │ 红墙 8/10 │ 步数:12 │   ← AppBar 信息
├─────────────────────────┤
│                         │
│     9×9 棋盘            │   ← Expanded(flex: 4)
│     (GameBoardWidget)   │
│                         │
├─────────────────────────┤
│  [走棋]  [放墙↕]  [重来] │   ← 底部操作栏 32dp
└─────────────────────────┘
```

- [ ] AppBar 显示: 当前模式、双方剩余墙壁数、回合计数
- [ ] AppBar 颜色指示当前轮到谁（蓝色/红色）
- [ ] 底部栏三个按钮:
  - [走棋] — `_isPlacingWall = false`
  - [放墙↕] — `_isPlacingWall = true`，并显示墙壁方向选择器
  - [重来] — 确认后 `GameEngine.initialize()`

---

## T8 — Service 适配

**文件**: `lib/core/surround_game/surround_game_service.dart`

### 8.1 executeAction
- [ ] 新增 `executeAction` 替代 `executeMove`：
  ```dart
  void executeAction({
    TurnAction action = TurnAction.move,
    int? targetCellId,
    int? wallX, int? wallY,
    WallOrientation? wallOrientation,
  });
  ```
  - action=move → `GameEngine.movePiece(state, targetCellId)`
  - action=placeWall → `GameEngine.placeWall(state, wallX, wallY, wallOrientation)`

### 8.2 startGame
- [ ] `startGame()` 改用 `GameEngine.initialize()`

### 8.3 保留
- [ ] `sendInputToHost()` 参数兼容（PlayerInput 的 direction 改为 targetCellId）
- [ ] `sendStateToClient()` 参数不变（toJson/fromJson 已更新）

---

## T9 — 删除旧文件

- [ ] 删除 `lib/core/surround_game/engine/collision_detector.dart`
- [ ] 检查并删除 `lib/core/surround_game/models/player_input.dart`（若不再使用）
  - 注: 如果联机需要走棋指令序列化，则保留并修改

---

## T10 — 编译验证

- [ ] `flutter analyze` — 0 error
- [ ] 检查删除文件后是否还有未被清理的 import
- [ ] `git add` 修改的文件 + `git rm` 删除的文件
- [ ] 运行本地游戏流程（进入围追堵截 → 本地对战 → 走棋/放墙/跳棋）

---

## 文件变更汇总

| 文件 | 操作 |
|------|------|
| `surround_game_constants.dart` | 全改 |
| `models/game_state.dart` | 全改 |
| `models/game_event.dart` | 全改 |
| `engine/collision_detector.dart` | **删除** |
| `engine/game_engine.dart` | 全改 |
| `engine/bfs_pathfinder.dart` | **新增** |
| `widgets/game_board_widget.dart` | 全改 |
| `pages/game_board_page.dart` | 全改 |
| `surround_game_service.dart` | 局部修改 |
| `surround_game.dart` | 更新导出 |
| `models/game_room.dart` | 保留 |
| `models/player_input.dart` | 保留或修改 |
| `pages/game_lobby_page.dart` | 保留 |
| `pages/game_room_page.dart` | 保留 |
| `widgets/direction_pad.dart` | 保留 |
