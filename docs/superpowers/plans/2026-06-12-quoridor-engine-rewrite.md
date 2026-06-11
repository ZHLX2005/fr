# Quoridor 引擎重写 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把现有"围追堵截"（20×15 + 同时走 + 留轨迹）替换为 Quoridor 引擎（9×9 + 轮流走 + 放墙），含完整单测 42 用例。

**Architecture:** 纯值对象 `GameState` 位于 `models/`；`BfsPathfinder` + `QuoridorEngine` 是纯函数静态类位于 `engine/`；旧 UI 移到 `_legacy/` 暂存。model 不依赖 engine，engine 依赖 model。

**Tech Stack:** Dart 3 (Dart 3.11+), `package:test`, `flutter_test` (仅用于分析), `package:flutter/material.dart` (PlaceholderPage)

**重要修正(spec-to-plan):**
- Swift `DataModel.swift:82-94` wallIds: 横向(h=true) = `[base-1, base, base+1]`、竖向(h=false) = `[base-17, base, base+17]`。spec 第七节写反了，plan 用正确公式。
- Swift `GameModel+Action.swift:23-52` removeNearLink 使用 `wall.id`（即 `x + y*9`，不是 wallGrid 里的 id）。
  - 横向墙切断 `(baseId, baseId+9)` 与 `(baseId+1, baseId+10)`
  - 竖向墙切断 `(baseId, baseId+1)` 与 `(baseId+9, baseId+10)`
- 墙壁坐标 x/y 范围在 `[0,7]`（+1 后墙占满 8 道），修正 Swift 的 `[0,8]` bug。

---

## Task 1: P0 — 整理 _legacy/ 目录

**Files:**
- Create: `lib/core/surround_game/_legacy/README.md`
- Move: `lib/core/surround_game/pages/game_board_page.dart` → `_legacy/`
- Move: `lib/core/surround_game/widgets/game_board_widget.dart` → `_legacy/`
- Move: `lib/core/surround_game/widgets/direction_pad.dart` → `_legacy/`
- Move: `lib/core/surround_game/engine/collision_detector.dart` → `_legacy/`
- Move: `lib/core/surround_game/engine/game_engine.dart` → `_legacy/`
- Move: `lib/core/surround_game/models/game_state.dart` → `_legacy/`
- Move: `lib/core/surround_game/models/game_event.dart` → `_legacy/`
- Modify: `lib/core/surround_game/surround_game.dart` — 只保留旧导出中尚未迁移的
- Modify: `lib/core/surround_game/pages/game_lobby_page.dart` — 跳转到 PlaceholderPage
- Modify: `lib/core/surround_game/pages/game_room_page.dart` — 跳转到 PlaceholderPage
- Modify: `lib/core/surround_game/surround_game_service.dart` — 删除 `executeMove`

- [ ] **Step 1: 创建 _legacy/ 目录并移入旧文件**

用 `mkdir` 创建目录，然后用 `git mv` 移入。每个 mov 保留 git history。

```bash
mkdir -p lib/core/surround_game/_legacy/widgets lib/core/surround_game/_legacy/pages lib/core/surround_game/_legacy/engine lib/core/surround_game/_legacy/models
git mv lib/core/surround_game/pages/game_board_page.dart lib/core/surround_game/_legacy/pages/
git mv lib/core/surround_game/widgets/game_board_widget.dart lib/core/surround_game/_legacy/widgets/
git mv lib/core/surround_game/widgets/direction_pad.dart lib/core/surround_game/_legacy/widgets/
git mv lib/core/surround_game/engine/collision_detector.dart lib/core/surround_game/_legacy/engine/
git mv lib/core/surround_game/engine/game_engine.dart lib/core/surround_game/_legacy/engine/
git mv lib/core/surround_game/models/game_state.dart lib/core/surround_game/_legacy/models/
git mv lib/core/surround_game/models/game_event.dart lib/core/surround_game/_legacy/models/
```

- [ ] **Step 2: 修正 _legacy/ 内文件的相对 import**

_legacy 内文件现在在 `surround_game/_legacy/` 子目录下。需要修正：

- `_legacy/engine/game_engine.dart`：`import '../surround_game_constants.dart'`（原来在同级 engine 时可以 `../surround_game_constants`，现在变成 `../../surround_game_constants.dart`）

运行以下命令检查所有 import 并修正，或直接在 IDE 中打开报错文件逐行修。

```bash
# 检查哪些文件还有未修正的 import
grep -rn "import '../" lib/core/surround_game/_legacy/
```

打开 `_legacy/engine/game_engine.dart`，把第 2 行从 `import '../surround_game_constants.dart'` 改为：
```dart
import '../../surround_game_constants.dart';
```

同理检查其他文件：
- `_legacy/engine/collision_detector.dart`：`../surround_game_constants.dart` → `../../surround_game_constants.dart`
- `_legacy/models/game_state.dart`：`../surround_game_constants.dart` → `../../surround_game_constants.dart`
- `_legacy/widgets/direction_pad.dart`：`../surround_game_constants.dart` → `../../surround_game_constants.dart`
- `_legacy/widgets/game_board_widget.dart`：引用的 `../engine/game_engine.dart` → `../../_legacy/engine/game_engine.dart`；`../models/game_state.dart` → `../../_legacy/models/game_state.dart`；`../surround_game_constants.dart` → `../../surround_game_constants.dart`
- `_legacy/pages/game_board_page.dart`：引用的 `../surround_game_constants.dart` → `../../surround_game_constants.dart`；`../surround_game_service.dart` → `../../surround_game_service.dart`；`../models/game_state.dart` → `../../_legacy/models/game_state.dart`；`../widgets/game_board_widget.dart` → `../../_legacy/widgets/game_board_widget.dart`；`../widgets/direction_pad.dart` → `../../_legacy/widgets/direction_pad.dart`

- [ ] **Step 3: 写 _legacy/README.md**

```markdown
# _legacy/ — 旧版围追堵截（存档区）

这些文件是旧版"围追堵截"（20×15 棋盘 + 同时走 + 留轨迹）的源代码。
它们已经不再被 `surround_game.dart` 导出，也不参与主编译。

**何时删除：** 下一轮 UI 重写（Quoridor 9×9 棋盘 + 墙壁交互）完成后，
新建的 game_board_page.dart / game_board_widget.dart / game_engine.dart（新版本）
补全后，此目录可整体删除。

**迁移记录：**
- P0 (2026-06-12): 旧文件移入存档，旧 constants 仍然保留（`Direction` 等）
- P1: constants 全改后，_legacy/ 仍然引用旧 constants
- 待 UI 重写完成：删除本目录
```

- [ ] **Step 4: 重写 surround_game.dart 导出**

```dart
/// 围追堵截游戏模块入口
///
/// 注意：本轮引擎重写阶段，_legacy/ 内的旧文件不再导出。
/// 下一轮 UI 重写时会重新补充 page/widget 的导出。

export 'surround_game_constants.dart';
export 'models/game_room.dart';
export 'models/player_input.dart';
export 'surround_game_service.dart';
export 'pages/game_lobby_page.dart';
export 'pages/game_room_page.dart';
export 'widgets/room_list_tile.dart';
```

- [ ] **Step 5: 修改 game_lobby_page.dart — 将开始游戏改为 Placeholder**

修改 `_startLocalGame` 方法，以及 `_navigateToRoom` 内部跳转。注意 `_startLocalGame` 引用了 `GameEngine.initialize()`（旧）和 `GameBoardPage`。

```dart
// 在文件顶部 import 后加（不用删 old import，后续报错删）
import 'package:flutter/material.dart';
import '../surround_game_service.dart';
// 删掉 '..engine/game_engine.dart' — 旧 engine 移到 _legacy
import '../../localnet/localnet_service.dart' show localnetService;
import '../models/game_room.dart';
import '../widgets/room_list_tile.dart';
// 删掉 'game_room_page.dart' — 下轮改
// 删掉 'game_board_page.dart' — 旧 page 移到 _legacy

// 取代 _startLocalGame 内的跳转
void _startLocalGame() {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const PlaceholderPage("Quoridor 重写中"),
    ),
  );
}
```

对 `_navigateToRoom` 也做同样修改。确保 `PlaceholderPage` 可用（它是 Flutter 内置 widget）。

需要 `import 'package:flutter/material.dart'` 已经有了。

- [ ] **Step 6: 修改 game_room_page.dart — 将开始游戏改为 Placeholder**

```dart
// 删掉 import '../models/game_room.dart'（目前只有 game_room.dart 仍存在，不动）
// 删掉 import 'game_board_page.dart'

  void _startCountdown() {
    // 不再 countdown，直接跳 Placeholder
    _startGame();
  }

  void _startGame() {
    // 旧的代码：final state = _service.startGame();
    // 直接跳 Placeholder
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const PlaceholderPage("Quoridor 重写中"),
      ),
    );
  }
```

需要保留 `_service.leaveRoom()` 调用、`SurroundGameConstants.countdownSeconds` 引用也被删。

注意 `_service.startGame()` 还在 surround_game_service 里，这里不再调用。

- [ ] **Step 7: 修改 surround_game_service.dart — 删除 executeMove**

找到 `executeMove` 方法（约 188-202 行），删除整个方法。由于 `Direction` 枚举还在旧 constants 里被 `_legacy/` 引用，不要删 `Direction` 枚举。

删除：
```dart
  /// 执行走棋
  /// [moves] 包含双方方向的 Map（Host 调用本地计算）
  void executeMove({
    required Direction hostDir,
    required Direction clientDir,
  }) {
    if (_currentGameState == null) return;

    final result = GameEngine.step(_currentGameState!, hostDir, clientDir);
    _currentGameState = result.newState;
    _gameStateController.add(result.newState);

    for (final event in result.events) {
      debugPrint('[SurroundGame] 事件: $event');
    }
  }
```

还需要删除开头的 `import 'engine/game_engine.dart'`（7-8 行），因为旧 engine 已移走。

- [ ] **Step 8: flutter analyze 确认 0 error**

```bash
flutter analyze
```

Expected: no issues found, or only warnings in _legacy/ (which are acceptable since those files won't be compiled in the normal export chain).

如果 _legacy/ 有 `unused_import` 等 warning，在 `analysis_options.yaml` 中加入：
```yaml
analyzer:
  exclude:
    - "lib/core/surround_game/_legacy/**"
```

但先确认是否真的有问题。最好是 0 error 0 warning。

- [ ] **Step 9: Commit**

```bash
git add lib/core/surround_game/_legacy/ lib/core/surround_game/surround_game.dart lib/core/surround_game/pages/game_lobby_page.dart lib/core/surround_game/pages/game_room_page.dart lib/core/surround_game/surround_game_service.dart
git rm --cached lib/core/surround_game/pages/game_board_page.dart lib/core/surround_game/widgets/game_board_widget.dart lib/core/surround_game/widgets/direction_pad.dart lib/core/surround_game/engine/collision_detector.dart lib/core/surround_game/engine/game_engine.dart lib/core/surround_game/models/game_state.dart lib/core/surround_game/models/game_event.dart
git commit -m "chore(surround_game): 旧 UI/engine 暂存到 _legacy/，准备 Quoridor 重写"
```

---

## Task 2: P1 — 常量 + 枚举

**Files:**
- Modify: `lib/core/surround_game/surround_game_constants.dart`（全改）

- [ ] **Step 1: 重写 surround_game_constants.dart**

```dart
/// 围追堵截 (Quoridor) 游戏全局常量
///
/// 棋盘编码说明：
///   - cellId = x + y * 9（Swift DataModel.swift:78 id 计算方式）
///     其中 x=column(0-8), y=row(0-8), 0,0 为左上角
///   - wallGridId = (x*2+1) + (y*2+1)*17（DataModel.swift:86 的 wallId）
///     17×17 墙壁网格，仅当 t=true（即 wall）时有效
///
/// 对齐参考：.claude/repo/Quoridor-ios/Quoridor/Classes/Models/

/// 墙壁方向
enum WallOrientation { horizontal, vertical }

/// 玩家当前回合的动作选择（UI 层用，引擎不强依赖）
enum TurnAction { move, placeWall }

/// 游戏状态
///
/// 注：Swift 拼写为 `Runing`（typo），新 Dart 代码改为正确的 `running`。
/// Swift 参考: GameModel.swift:123-139
enum GameStatus { running, topWin, bottomWin, draw }

/// 格子状态（UI 渲染用，本轮暂不进入引擎核心数据）
enum CellState {
  empty,
  playerTop,
  playerBottom,
  validMove,
  invalidWall,
}

/// 围追堵截 (Quoridor) 游戏常量
class SurroundGameConstants {
  SurroundGameConstants._();

  // ─── 棋盘尺寸 ───
  /// 9×9 棋子网格（Swift 全局常量 boardSize = 9）
  static const int boardSize = 9;

  /// 81 个格子，cellId = 0..80
  static const int totalCells = 81;

  /// 17×17 墙壁网格（= boardSize * 2 - 1）
  static const int wallGridSize = 17;

  /// 289 个墙壁单元，wallGridId = 0..288
  static const int totalWallCells = 289;

  /// 每人 10 块挡板（标准 Quoridor 规则）
  static const int wallCountPerPlayer = 10;

  // ─── 起始位置（Swift GameModel.swift:163-164）───
  /// 上方玩家起始 cellId = 4（x=4, y=0）
  static const int topPlayerStart = 4;

  /// 下方玩家起始 cellId = 76（x=4, y=8）
  static const int bottomPlayerStart = 76;

  // ─── 胜负目标行 ───
  /// top 到达 y=8 → cellId ∈ [72, 80]
  static const int topGoalRow = 8;

  /// bottom 到达 y=0 → cellId ∈ [0, 8]
  static const int bottomGoalRow = 0;

  // ─── 保留：surround_game_service 仍在用 ───
  static const String kPathGameInfo = '/api/game/info';
  static const String kPathGameJoin = '/api/game/join';
  static const String kPathGameLeave = '/api/game/leave';
  static const String kPathGameSync = '/api/game/sync';
  static const String kPathGameInput = '/api/game/input';
  static const String kBroadcastGame = 'g';
  static const String kBroadcastRoom = 'r';
  static const String kBroadcastPlayers = 'p';
  static const String kGameType = 'surround';
  static const int kMaxPlayers = 2;
}
```

- [ ] **Step 2: flutter analyze 确认**

```bash
flutter analyze
```

Expected: 0 issues. _legacy/ 内的旧文件引用旧 constants（如 `Direction`），但旧 constants 在此轮还没删（只是文件内容被重写），_legacy 自然找不到旧枚举了。

这会产生 error：_legacy 引用的 `Direction` 现在不存在了。

**解决方案**：在新 constants 里保留一个 `@Deprecated` 的 `Direction` 枚举，声明周期只到 _legacy 被删除：

```dart
/// @deprecated 仅用于 _legacy/ 编译过渡，下轮删除。
@Deprecated('迁移到 CellState / WallOrientation')
enum Direction { up, down, left, right }
```

同样保留 `RoomState`、`PlayerId`：

```dart
@Deprecated('旧版房间状态，下轮删除')
enum RoomState { waiting, countdown, playing, finished }

@Deprecated('旧版玩家编号，下轮删除')
enum PlayerId { host, client }
```

保留旧常量字段（也 `@Deprecated`）：

```dart
@Deprecated('旧棋盘尺寸，下轮删除')
static const int boardRows = 20;
@Deprecated('旧棋盘尺寸，下轮删除')
static const int boardCols = 15;
@Deprecated('旧起始位置，下轮删除')
static const int hostStartRow = 1;
@Deprecated('旧起始位置，下轮删除')
static const int hostStartCol = 1;
@Deprecated('旧起始位置，下轮删除')
static const int clientStartRow = 18;
@Deprecated('旧起始位置，下轮删除')
static const int clientStartCol = 13;
@Deprecated('旧积分制，下轮删除')
static const int winScore = 3;
@Deprecated('旧倒计时，下轮删除')
static const int countdownSeconds = 3;
@Deprecated('旧超时，下轮删除')
static const int clientTimeoutSeconds = 30;
```

这样 _legacy 编译不报错，new code 也不会误用。

- [ ] **Step 3: flutter analyze 确认 0 issue**

```bash
flutter analyze
```

Expected: 0 errors, 0 warnings（`@Deprecated` 可能产生 info，但不产生 error）。

- [ ] **Step 4: Commit**

```bash
git add lib/core/surround_game/surround_game_constants.dart
git commit -m "feat(surround_game): 重写常量与 Quoridor 枚举（boardSize=9, wallGrid=17）"
```

---

## Task 3: P2 — GameState + MoveRecord + GameEvent + 单测

**Files:**
- Create: `lib/core/surround_game/models/game_state.dart`（全新）
- Create: `lib/core/surround_game/models/game_event.dart`（全新）
- Create: `test/core/surround_game/game_state_test.dart`
- Modify: `pubspec.yaml`（确保 dev_dependencies 有 `test`— 已依赖 `flutter_test`，OK）

- [ ] **Step 1: 写 game_event.dart**

```dart
/// 游戏事件模型
///
/// sealed class 确保事件类型是穷举的（Dart 3 feature）。
/// 配合 switch 的 exhaustive 检查，UI 层处理事件时不会漏分支。
///
/// 本轮在引擎层产生事件，但不强依赖（引擎纯函数返回 new state，
/// 事件仅用于日志/动画触发，非必要）。
sealed class GameEvent {
  const GameEvent();
}

/// 棋子从 fromCellId 移动到 toCellId
class PieceMovedEvent extends GameEvent {
  final int fromCellId;
  final int toCellId;
  final bool isTopPlayer;

  const PieceMovedEvent({
    required this.fromCellId,
    required this.toCellId,
    required this.isTopPlayer,
  });

  @override
  String toString() =>
      'PieceMoved(${isTopPlayer ? "top" : "bottom"}: $fromCellId → $toCellId)';
}

/// 在格点 (x, y) 放置了 orientation 方向的墙壁
class WallPlacedEvent extends GameEvent {
  final int x;
  final int y;
  final WallOrientation orientation;
  final bool isTopPlayer;

  const WallPlacedEvent({
    required this.x,
    required this.y,
    required this.orientation,
    required this.isTopPlayer,
  });

  @override
  String toString() =>
      'WallPlaced(${isTopPlayer ? "top" : "bottom"}: ($x,$y) $orientation)';
}

/// 游戏结束
class GameOverEvent extends GameEvent {
  final GameStatus status; // topWin / bottomWin / draw

  const GameOverEvent({required this.status});

  @override
  String toString() => 'GameOver($status)';
}
```

- [ ] **Step 2: 写 game_state.dart**

```dart
import 'game_event.dart';
import '../surround_game_constants.dart';

/// 棋谱栈记录（Swift DataModel）
///
/// 同时表示「棋子移动」和「墙壁放置」。
/// history 中按时间顺序存储每次操作。
///
/// Swift 参考：DataModel.swift（id, x, y, h, t 字段）
///   t=false → 棋子，t=true → 墙壁
///   h=棋盘 → 上方/横向，h=false → 下方/竖向
class MoveRecord {
  /// 墙壁格点坐标 x (0-8)，或走棋后 cellId % 9
  final int x;

  /// 墙壁格点坐标 y (0-8)，或走棋后 cellId ~/ 9
  final int y;

  /// true=放墙, false=走棋
  final bool isWall;

  /// 仅 isWall=true 时有值，方向（横向/竖向）
  final WallOrientation? orientation;

  /// 哪方的操作
  final bool isTopPlayer;

  const MoveRecord({
    required this.x,
    required this.y,
    required this.isWall,
    required this.isTopPlayer,
    this.orientation,
  });

  /// 走棋记录工厂
  factory MoveRecord.move({
    required int cellId,
    required bool isTopPlayer,
  }) =>
      MoveRecord(
        x: cellId % 9,
        y: cellId ~/ 9,
        isWall: false,
        isTopPlayer: isTopPlayer,
      );

  /// 放墙记录工厂
  factory MoveRecord.wall({
    required int x,
    required int y,
    required WallOrientation orientation,
    required bool isTopPlayer,
  }) =>
      MoveRecord(
        x: x,
        y: y,
        isWall: true,
        orientation: orientation,
        isTopPlayer: isTopPlayer,
      );

  /// 序列化为 Map
  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'isWall': isWall,
        'orientation': orientation?.name,
        'isTopPlayer': isTopPlayer,
      };

  /// 反序列化
  factory MoveRecord.fromJson(Map<String, dynamic> json) => MoveRecord(
        x: json['x'] as int,
        y: json['y'] as int,
        isWall: json['isWall'] as bool,
        orientation: json['orientation'] != null
            ? WallOrientation.values.firstWhere(
                (e) => e.name == json['orientation'],
              )
            : null,
        isTopPlayer: json['isTopPlayer'] as bool,
      );

  @override
  String toString() =>
      'MoveRecord(${isTopPlayer ? "top" : "bottom"} ${isWall ? "wall" : "piece"} ($x,$y)${isWall ? " $orientation" : ""})';
}

/// Quoridor 游戏状态 — 不可变值对象
///
/// 内部容器按约定不可变：
///   - 引擎所有 mutator 都返回 copyWith 后的新 GameState
///   - 不暴露能修改容器的接口（adjacency/wallGrid 等直接暴露但约定只读）
///   - 测试和业务代码不要直接 .add() 或 [idx] = x
///
/// 所有构造逻辑（initialize、fromBoardSpec、邻接表构建）集中在
/// QuoridorEngine，避免 model 反向依赖 engine。
///
/// Swift 参考：
///   DataModel.swift — id, x, y, h, t 编码
///   GameModel.swift:142 — gameNears（adjacency 对应）
///   GameModel.swift:145 — gameWalls（wallGrid 对应）
///   GameModel.swift:113 — gameStack（history 对应）
class GameState {
  /// 81 个格子的邻接表（Swift gameNears）
  /// adjacency[i] = 与 i 直接相通的 cellId 集合（不可变约定）
  final List<Set<int>> adjacency;

  /// 289 个墙壁单元的占用标志（Swift gameWalls）
  /// wallGrid[id] = true 表示该墙壁格被占用，id=wallBaseId(x,y)+偏移
  final List<bool> wallGrid;

  /// 上方棋子位置 cellId（x + y*9, 0..80）
  final int topPlayerId;

  /// 下方棋子位置 cellId
  final int bottomPlayerId;

  /// true=当前轮到上方玩家操作, false=轮到下方玩家
  final bool currentPlayerIsTop;

  /// 上方已放置的墙壁数（≤ wallCountPerPlayer）
  final int topWallsPlaced;

  /// 下方已放置的墙壁数
  final int bottomWallsPlaced;

  /// 棋谱栈（Swift gameStack）
  /// 按时间顺序记录每次走棋/放墙操作。本轮仅追加、不实现 undo（悔棋）。
  /// toJson 序列化它，为下轮 LAN 同步预留。
  final List<MoveRecord> history;

  /// 游戏状态
  final GameStatus status;

  /// 当前玩家可走到的格子集合（含跳跃规则）
  /// 在 switchTurn 时由引擎重算并缓存，避免 UI 每帧重算
  final Set<int> validMoves;

  const GameState({
    required this.adjacency,
    required this.wallGrid,
    required this.topPlayerId,
    required this.bottomPlayerId,
    required this.currentPlayerIsTop,
    required this.topWallsPlaced,
    required this.bottomWallsPlaced,
    required this.history,
    required this.status,
    required this.validMoves,
  });

  /// 创建新 GameState，成功拷贝传入参数
  GameState copyWith({
    List<Set<int>>? adjacency,
    List<bool>? wallGrid,
    int? topPlayerId,
    int? bottomPlayerId,
    bool? currentPlayerIsTop,
    int? topWallsPlaced,
    int? bottomWallsPlaced,
    List<MoveRecord>? history,
    GameStatus? status,
    Set<int>? validMoves,
  }) =>
      GameState(
        adjacency: adjacency ?? this.adjacency,
        wallGrid: wallGrid ?? this.wallGrid,
        topPlayerId: topPlayerId ?? this.topPlayerId,
        bottomPlayerId: bottomPlayerId ?? this.bottomPlayerId,
        currentPlayerIsTop:
            currentPlayerIsTop ?? this.currentPlayerIsTop,
        topWallsPlaced: topWallsPlaced ?? this.topWallsPlaced,
        bottomWallsPlaced: bottomWallsPlaced ?? this.bottomWallsPlaced,
        history: history ?? this.history,
        status: status ?? this.status,
        validMoves: validMoves ?? this.validMoves,
      );

  /// 序列化为 JSON Map
  Map<String, dynamic> toJson() => {
        'topPlayerId': topPlayerId,
        'bottomPlayerId': bottomPlayerId,
        'currentPlayerIsTop': currentPlayerIsTop,
        'topWallsPlaced': topWallsPlaced,
        'bottomWallsPlaced': bottomWallsPlaced,
        'history': history.map((m) => m.toJson()).toList(),
        'status': status.name,
        'validMoves': validMoves.toList(),
        // 注意：adjacency 和 wallGrid 不序列化（由 QuoridorEngine 从
        // history 重放重建）。validMoves 序列化作为 hints。
        // 如果需要 full state 远程重建，需要序列化 wallGrid。
        // 下轮 LAN 同步时补充。
      };

  /// 反序列化
  ///
  /// 注意：deserialize 后的 state **不保证** adjacency 和 wallGrid 正确。
  /// 上轮要用 QuoridorEngine.replayHistory(history) 重建。
  /// 这局限将在下轮 LAN 同步时解决。
  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
        topPlayerId: json['topPlayerId'] as int,
        bottomPlayerId: json['bottomPlayerId'] as int,
        currentPlayerIsTop: json['currentPlayerIsTop'] as bool,
        topWallsPlaced: json['topWallsPlaced'] as int? ?? 0,
        bottomWallsPlaced: json['bottomWallsPlaced'] as int? ?? 0,
        history: (json['history'] as List?)
                ?.map((m) => MoveRecord.fromJson(m as Map<String, dynamic>))
                .toList() ??
            [],
        status: GameStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => GameStatus.running,
        ),
        validMoves: (json['validMoves'] as List?)
                ?.map((e) => e as int)
                .toSet() ??
            {},
        adjacency: List.generate(81, (_) => <int>{}),
        wallGrid: List.filled(289, false),
      );
}
```

- [ ] **Step 3: 写 game_state_test.dart（用例 26-28 + 30-31 = 5 用例）**

```dart
import 'dart:convert';
import 'package:test/test.dart';

// 需要 import 新文件
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';

void main() {
  group('GameState', () {
    test('构造含默认字段 → 字段值正确', () {
      final state = GameState(
        adjacency: List.generate(81, (_) => <int>{}),
        wallGrid: List.filled(289, false),
        topPlayerId: 4,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
        topWallsPlaced: 0,
        bottomWallsPlaced: 0,
        history: const [],
        status: GameStatus.running,
        validMoves: {13, 3, 5},
      );

      expect(state.topPlayerId, 4);
      expect(state.bottomPlayerId, 76);
      expect(state.currentPlayerIsTop, true);
      expect(state.status, GameStatus.running);
      expect(state.validMoves, containsAll([13, 3, 5]));
      expect(state.adjacency.length, 81);
      expect(state.wallGrid.length, 289);
    });

    test('copyWith 只修改单字段', () {
      final state = GameState(
        adjacency: List.generate(81, (_) => <int>{}),
        wallGrid: List.filled(289, false),
        topPlayerId: 4,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
        topWallsPlaced: 0,
        bottomWallsPlaced: 0,
        history: const [],
        status: GameStatus.running,
        validMoves: {13, 3, 5},
      );

      final modified = state.copyWith(topPlayerId: 13);
      expect(modified.topPlayerId, 13, reason: 'topPlayerId 应更新');
      expect(state.bottomPlayerId, 76, reason: '原对象 bottom 不变');
      expect(state.currentPlayerIsTop, true, reason: '原对象不变');
    });

    test('toJson → fromJson 往返一致', () {
      final state = GameState(
        adjacency: List.generate(81, (_) => <int>{}),
        wallGrid: List.filled(289, false),
        topPlayerId: 4,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
        topWallsPlaced: 0,
        bottomWallsPlaced: 0,
        history: [
          MoveRecord.move(cellId: 13, isTopPlayer: true),
        ],
        status: GameStatus.running,
        validMoves: {13, 3, 5},
      );

      final json = state.toJson();
      final decoded = GameState.fromJson(json);

      expect(decoded.topPlayerId, state.topPlayerId);
      expect(decoded.bottomPlayerId, state.bottomPlayerId);
      expect(decoded.currentPlayerIsTop, state.currentPlayerIsTop);
      expect(decoded.status, state.status);
      expect(decoded.history.length, 1);
      expect(decoded.history[0].isWall, false);
    });
  });

  group('MoveRecord', () {
    test('move 工厂设置正确字段', () {
      final record = MoveRecord.move(cellId: 13, isTopPlayer: true);
      expect(record.x, 4, reason: 'cellId=13 → x=13%9=4');
      expect(record.y, 1, reason: 'cellId=13 → y=13~/9=1');
      expect(record.isWall, false);
      expect(record.isTopPlayer, true);
      expect(record.orientation, isNull);
    });

    test('wall 工厂设置正确字段', () {
      final record = MoveRecord.wall(
        x: 3,
        y: 4,
        orientation: WallOrientation.horizontal,
        isTopPlayer: false,
      );
      expect(record.x, 3);
      expect(record.y, 4);
      expect(record.isWall, true);
      expect(record.isTopPlayer, false);
      expect(record.orientation, WallOrientation.horizontal);
    });

    test('MoveRecord toJson → fromJson 往返', () {
      final original = MoveRecord.wall(
        x: 2,
        y: 5,
        orientation: WallOrientation.vertical,
        isTopPlayer: true,
      );
      final json = original.toJson();
      final decoded = MoveRecord.fromJson(json);
      expect(decoded.x, original.x);
      expect(decoded.y, original.y);
      expect(decoded.isWall, original.isWall);
      expect(decoded.orientation, original.orientation);
      expect(decoded.isTopPlayer, original.isTopPlayer);
    });
  });
}
```

- [ ] **Step 4: 确认 test 目录结构存在**

```bash
mkdir -p test/core/surround_game
```

- [ ] **Step 5: 运行单测试验证失败但能运行**

```bash
flutter test test/core/surround_game/game_state_test.dart
```

Expected: 6 tests all pass（but we have 7 test cases — 3 for GameState + 4 for MoveRecord = 7）。

Actually count: 3 GameState tests + 3 MoveRecord tests = 6 tests（copyWith + construct + json 往返 + move工厂 + wall工厂 + 记录往返）。

Wait, let me regroup carefully:

```dart
group('GameState', () {
  test('构造 → 字段正确', ...);     // 1
  test('copyWith 单字段', ...);    // 2
  test('toJson/fromJson 往返', ...); // 3
});
group('MoveRecord', () {
  test('move 工厂', ...);          // 4
  test('wall 工厂', ...);          // 5
  test('json 往返', ...);          // 6
});
```

6 tests. Run:

```bash
flutter test test/core/surround_game/game_state_test.dart -v
```

Expected: all 6 PASS.

- [ ] **Step 6: flutter analyze 确认**

```bash
flutter analyze
```

Expected: 0 errors.

- [ ] **Step 7: Commit**

```bash
git add lib/core/surround_game/models/game_state.dart lib/core/surround_game/models/game_event.dart test/core/surround_game/game_state_test.dart
git commit -m "feat(surround_game): GameState + MoveRecord + GameEvent (含单测 6 用例)"
```

---

## Task 4: P3 — BFS Pathfinder + 单测

**Files:**
- Create: `lib/core/surround_game/engine/bfs_pathfinder.dart`
- Create: `test/core/surround_game/bfs_pathfinder_test.dart`
- Modify: `lib/core/surround_game/surround_game.dart`（新增导出— 需等 engine 创建后加）

- [ ] **Step 1: 看 Swift 参考理解 BFS 实现**

Swift `GameAi.swift:226-266`：

```swift
private class func pathForPlayer(player: Node, end: (Int)->Bool) -> [Int] {
    var logs = [player]       // 已访问 + 父指针
    var queue = [player]      // BFS 队列
    var finish: Node?

    while !queue.isEmpty {
        let path = queue.removeFirst()
        if end(path.data) {
            finish = path
            break
        } else {
            let near = GameModel.shared.gameNears[path.data]
            for n in near {
                if !logs.contains({ $0.data == n }) {
                    logs.append(Node(data: n, parent: path.data))
                    queue.append(Node(data: n, parent: path.data))
                }
            }
        }
    }
    // backtrack
    if let _ = finish {
        var node = finish!
        var path = [node.data]
        while node.parent != -1 {
            if let log = logs.indexOf({ $0.data == node.parent }) {
                node = logs[log]
                path.insert(node.data, atIndex: 0)
            } else { break }
        }
        return path
    }
    return []
}
```

核心：`Node(data: parent:)` 是自定义节点 struct，`logs` 同时作 visited 和 parent 回溯。

- [ ] **Step 2: 写 bfs_pathfinder.dart**

```dart
import '../models/game_state.dart';
import '../surround_game_constants.dart';

/// BFS 寻路器 — 纯函数静态类
///
/// 职责：
///   1. 给定邻接表和起点，找最短路径到对方底线
///   2. 判定路径存在性（墙壁合法性的核心条件）
///
/// Swift 对应：GameAi.swift:226-266 pathForPlayer
///
/// 算法：标准 BFS + 父指针回溯
///   - 队列存 (cellId, parentIndex) — parentIndex 指向 logs 数组的索引
///   - 已访问标记用 List<(cellId, parent)> 的 logs
///   - 找到第一个满足"到达对方底线"的节点 → 回溯链
///
/// 性能：9×9 棋盘最坏 81 节点 + 平均度数 ≤ 4，单次 BFS < 0.1ms
class BfsPathfinder {
  BfsPathfinder._();

  /// BFS 内部的搜索节点
  @pragma('vm:prefer-inline')
  static const int _noParent = -1;

  /// 找从 start 到对方底线的最短路径
  ///
  /// [adjacency] 81 长度的邻接表
  /// [start]     起点 cellId（0-80）
  /// [isTopPlayer] true=上方玩家（目标 y=8，即 cellId ≥ 72）
  ///                false=下方玩家（目标 y=0，即 cellId ≤ 8）
  ///
  /// 返回路径（含 start 和终点），不可达返回空列表
  /// 路径保证最短（BFS 按层扩展，首次遇到终点即最短）
  ///
  /// Swift 参考：GameAi.swift:226-266 pathForPlayer
  static List<int> findShortestPath(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  ) {
    // 终点判定函数：top 玩家看 cellId >= 72 (y=8)
    // bottom 玩家看 cellId <= 8 (y=0)
    bool isGoal(int cellId) =>
        isTopPlayer ? cellId >= 72 : cellId <= 8;

    // 如果起点就是终点
    if (isGoal(start)) return [start];

    // logs 数组存 (cellId, parentIndex)
    // parentIndex 指向 logs 中父节点的索引，_noParent 表示根
    final logs = <_LogEntry>[];
    final queue = <int>[]; // 存索引到 logs

    logs.add(_LogEntry(data: start, parent: _noParent));
    queue.add(0); // 根节点在 logs[0]

    int head = 0; // 队列头指针（避免 removeFirst 的 O(n) 开销）

    // BFS 主循环
    while (head < queue.length) {
      final currentIndex = queue[head];
      head++;
      final current = logs[currentIndex];

      final neighbors = adjacency[current.data];
      for (final neighbor in neighbors) {
        if (isGoal(neighbor)) {
          // 找到终点 → 回溯路径
          final result = <int>[neighbor, current.data];
          int parent = current.parent;
          while (parent != _noParent) {
            result.add(logs[parent].data);
            parent = logs[parent].parent;
          }
          return result.reversed.toList();
        }

        // 未访问过
        if (!logs.any((e) => e.data == neighbor)) {
          logs.add(_LogEntry(data: neighbor, parent: currentIndex));
          queue.add(logs.length - 1);
        }
      }
    }

    return const []; // 不可达
  }

  /// 路径存在性检查（findShortestPath 的轻量封装）
  static bool hasPathToGoal(
    List<Set<int>> adjacency,
    int start,
    bool isTopPlayer,
  ) {
    return findShortestPath(adjacency, start, isTopPlayer).isNotEmpty;
  }

  /// 双方都能到达自己的终点（墙壁合法性校验的核心判定）
  ///
  /// 先用 BFS 检查 top 能否到 y=8，再检查 bottom 能否到 y=0。
  /// 只要有一方不可达即返回 false。
  ///
  /// Swift 参考：GameModel.swift:61-78 iWallIsAllow
  static bool bothPlayersHavePath(
    List<Set<int>> adjacency,
    int topPlayerId,
    int bottomPlayerId,
  ) {
    return hasPathToGoal(adjacency, topPlayerId, true) &&
        hasPathToGoal(adjacency, bottomPlayerId, false);
  }
}

/// BFS 内部日志条目
class _LogEntry {
  final int data;   // cellId
  final int parent; // logs 中的父节点索引

  const _LogEntry({required this.data, required this.parent});
}
```

- [ ] **Step 3: 建 engine 目录（如果没有）**

```bash
mkdir -p lib/core/surround_game/engine
```

- [ ] **Step 4: 写 bfs_pathfinder_test.dart（10 用例）**

```dart
import 'package:test/test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/bfs_pathfinder.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';
// 暂借 QuoridorEngine 的 buildInitialAdjacency — 但本轮 P4a 还没出
// 所以手动构造标准邻接表

/// 构造标准 9×9 四连通邻接表（参考 GameModel.swift:186-202）
List<Set<int>> _emptyAdjacency() {
  final adj = List.generate(81, (i) => <int>{});
  for (int i = 0; i < 81; i++) {
    final x = i % 9;
    final y = i ~/ 9;
    if (x > 0) adj[i].add(i - 1);     // 左
    if (x < 8) adj[i].add(i + 1);     // 右
    if (y > 0) adj[i].add(i - 9);     // 上
    if (y < 8) adj[i].add(i + 9);     // 下
  }
  return adj;
}

/// 构造 y=4 全行横墙隔断的邻接表
/// 每道横墙在 y=4，x 从 0 到 6，步长 2
/// 横墙切断 (baseId, baseId+9) 和 (baseId+1, baseId+10)
List<Set<int>> _fullBlockAdjacency() {
  final adj = _emptyAdjacency();
  // y=4, x=0,2,4,6 共 4 块横墙，将 9×9 分为上下两部分
  for (int x = 0; x <= 6; x += 2) {
    final baseId = x + 4 * 9; // x + y*9
    // 切断 (baseId, baseId+9) 和 (baseId+1, baseId+10)
    adj[baseId].remove(baseId + 9);
    adj[baseId + 9].remove(baseId);
    adj[baseId + 1].remove(baseId + 10);
    adj[baseId + 10].remove(baseId + 1);
  }
  return adj;
}

void main() {
  group('findShortestPath', () {
    test('空棋盘 top 在 (4,0) → 长度 9 (直走 8 步)', () {
      final adj = _emptyAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 4, true);
      expect(path.length, 9, reason: '空棋盘直走 8 步含起点共 9 节点');
      expect(path.first, 4, reason: '起点应保留');
      expect(path.last >= 72, true, reason: '终点必在 y=8 行');
      // 路径应为 [4, 13, 22, 31, 40, 49, 58, 67, 76]（直下）
      expect(path, [4, 13, 22, 31, 40, 49, 58, 67, 76]);
    });

    test('空棋盘 bottom 在 (4,8) → 长度 9 (直上 8 步)', () {
      final adj = _emptyAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 76, false);
      expect(path.length, 9);
      expect(path.first, 76);
      expect(path.last <= 8, true, reason: '终点必在 y=0 行');
      expect(path, [76, 67, 58, 49, 40, 31, 22, 13, 4]);
    });

    test('top 已在 y=8 (cellId=76) → 长度 1', () {
      final adj = _emptyAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 76, true);
      expect(path, [76], reason: '起点即终点');
    });

    test('全墙隔断 → 空列表', () {
      final adj = _fullBlockAdjacency();
      final path = BfsPathfinder.findShortestPath(adj, 4, true);
      expect(path, isEmpty, reason: 'y=4 全横墙阻断 top 到底线');
    });

    test('单道横墙在 y=4 仍能绕 → 非空且路径 > 9', () {
      final adj = _emptyAdjacency();
      // 只有 x=4 的一道横墙（不是全行阻断）
      final baseId = 4 + 4 * 9; // cellId = 40
      adj[baseId].remove(baseId + 9);
      adj[baseId + 9].remove(baseId);
      adj[baseId + 1].remove(baseId + 10);
      adj[baseId + 10].remove(baseId + 1);

      final path = BfsPathfinder.findShortestPath(adj, 4, true);
      expect(path, isNotEmpty, reason: '单一横墙可以绕');
      expect(path.length, greaterThan(9), reason: '绕路所以 > 9 步');
    });
  });

  group('hasPathToGoal', () {
    test('空棋盘 → true', () {
      expect(
        BfsPathfinder.hasPathToGoal(_emptyAdjacency(), 4, true),
        true,
      );
    });

    test('全隔断 → false', () {
      expect(
        BfsPathfinder.hasPathToGoal(_fullBlockAdjacency(), 4, true),
        false,
      );
    });
  });

  group('bothPlayersHavePath', () {
    test('空棋盘 → true', () {
      expect(
        BfsPathfinder.bothPlayersHavePath(_emptyAdjacency(), 4, 76),
        true,
      );
    });

    test('只阻断 top → false', () {
      expect(
        BfsPathfinder.bothPlayersHavePath(_fullBlockAdjacency(), 4, 76),
        false,
      );
    });

    test('bothPlayersHavePath: 双方都被阻断 → false', () {
      // _fullBlockAdjacency 在 y=4 放全行横墙阻断上下通透
      // top=72(y=8, 已到目标行) 不受影响 → hasPathToGoal=true
      // bottom=76(y=8, 需要走到 y=0) 被 y=4 横墙隔断 → hasPathToGoal=false
      // → bothPlayersHavePath=false
      final adj = _fullBlockAdjacency();
      expect(
        BfsPathfinder.bothPlayersHavePath(adj, 72, 76),
        false,
      );
    });
  });
}
```

- [ ] **Step 6: 运行单测**

```bash
flutter test test/core/surround_game/bfs_pathfinder_test.dart -v
```

Expected: 10 tests all PASS.

如果某个不通过（比如第 10 个的逻辑或第 5 个的绕路判断），逐条调试。

- [ ] **Step 7: flutter analyze**

```bash
flutter analyze
```

Expected: 0 errors.

- [ ] **Step 8: Commit**

```bash
git add lib/core/surround_game/engine/bfs_pathfinder.dart test/core/surround_game/bfs_pathfinder_test.dart
git commit -m "feat(surround_game): BFS pathfinder (含单测 10 用例)"
```

---

## Task 5: P4a — QuoridorEngine 走棋 + 跳跃 + 换手 + 单测

**Files:**
- Create: `lib/core/surround_game/engine/game_engine.dart`
- Modify: `test/core/surround_game/game_state_test.dart`（加用例 29 fromBoardSpec）
- Create: `test/core/surround_game/game_engine_test.dart`（前 15 用例）

- [ ] **Step 1: 完善 game_engine.dart — 初始化 + 邻接 + ID 计算**

```dart
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

  /// 切换回合
  ///
  /// - 翻转 currentPlayerIsTop
  /// - 重算 validMoves（调用 getValidMoves）
  /// - 重算 status（调用 checkStatus）
  ///
  /// 不在 movePiece/placeWall 里自动换手是为了：
  ///   1. 让单测能分别验证"动作"和"换手"
  ///   2. 让网络层有机会在换手前广播状态
  ///
  /// Swift 参考：GameModel.swift:117-120 player 属性
  ///   Swift 通过 gameStack.count 的奇偶判断，我们显式翻转 counter
  static GameState switchTurn(GameState state) {
    final nextIsTop = !state.currentPlayerIsTop;
    final playerId = nextIsTop ? state.topPlayerId : state.bottomPlayerId;
    final opponentId = nextIsTop ? state.bottomPlayerId : state.topPlayerId;

    final moves = getValidMoves(state.adjacency, playerId, opponentId);
    final status = checkStatus(
      state.adjacency, state.topPlayerId, state.bottomPlayerId,
    );

    return state.copyWith(
      currentPlayerIsTop: nextIsTop,
      validMoves: moves,
      status: status,
    );
  }

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
```

- [ ] **Step 2: 完善 surround_game.dart 导出**

在现有 `surround_game.dart` 中追加新文件的导出：

```dart
// 追加：
export 'models/game_state.dart';
export 'models/game_event.dart';
export 'engine/bfs_pathfinder.dart';
export 'engine/game_engine.dart';
```

- [ ] **Step 3: 补 game_state_test.dart 用例 29（fromBoardSpec）**

在 `game_state_test.dart` 的 `group('GameState', ...)` 末尾追加：

```dart
    test('fromBoardSpec 构造测试局面 → adjacency 与 wallGrid 一致', () {
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 4,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
        placedWalls: [
          (x: 3, y: 4, o: WallOrientation.horizontal),
        ],
      );
      expect(state.topPlayerId, 4);
      expect(state.bottomPlayerId, 76);
      expect(state.adjacency.length, 81);
      expect(state.wallGrid.length, 289);
      // 横墙 (3,4) 占用了 3 个 wallGrid 单元
      // wallBaseId(3,4) = (3*2+1)+(4*2+1)*17 = 7+9*17 = 7+153 = 160
      // horizontal → [159, 160, 161]
      expect(state.wallGrid[159], true, reason: '横墙左');
      expect(state.wallGrid[160], true, reason: '横墙中');
      expect(state.wallGrid[161], true, reason: '横墙右');
      // 横墙切断 (baseId, baseId+9) 和 (baseId+1, baseId+10)
      // baseId = x + y*9 = 3+4*9 = 39
      // 切断 (39,48) 和 (40,49)
      expect(state.adjacency[39].contains(48), false);
      expect(state.adjacency[40].contains(49), false);
    });
```

在文件顶部的 import 加上 `QuoridorEngine`：

```dart
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
```

- [ ] **Step 4: 写 game_engine_test.dart — 初始化 + 基础 + 走棋 + 跳跃 + 换手 + 邻接（15 用例）**

```dart
import 'package:test/test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/bfs_pathfinder.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';

void main() {
  group('初始化与基础', () {
    test('initialize → top=4, bottom=76, status=running, currentPlayerIsTop=true', () {
      final state = QuoridorEngine.initialize();
      expect(state.topPlayerId, 4, reason: 'top 起始 x=4,y=0 → id=4');
      expect(state.bottomPlayerId, 76, reason: 'bottom 起始 x=4,y=8 → id=76');
      expect(state.currentPlayerIsTop, true);
      expect(state.status, GameStatus.running);
      expect(state.topWallsPlaced, 0);
      expect(state.bottomWallsPlaced, 0);
      expect(state.history, isEmpty);
      expect(state.validMoves, isNotEmpty, reason: '初始有可走格子');
    });

    test('buildInitialAdjacency → 角点度数 2, 边格 3, 中心 4', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      // 角点 (0,0) cellId=0
      expect(adj[0].length, 2, reason: '0,0 只连右和下');
      expect(adj[0].contains(1), true);
      expect(adj[0].contains(9), true);
      // 边格 (4,0) cellId=4
      expect(adj[4].length, 3, reason: '4,0 连左、右、下');
      expect(adj[4].contains(3), true);
      expect(adj[4].contains(5), true);
      expect(adj[4].contains(13), true);
      // 中心 (4,4) cellId=40
      expect(adj[40].length, 4, reason: '4,4 连上下左右');
      expect(adj[40].contains(39), true); // 左
      expect(adj[40].contains(41), true); // 右
      expect(adj[40].contains(31), true); // 上
      expect(adj[40].contains(49), true); // 下
    });

    test('wallBaseId', () {
      // wallBaseId(0,0) = (0*2+1)+(0*2+1)*17 = 1+17 = 18
      expect(QuoridorEngine.wallBaseId(0, 0), 18);
      // wallBaseId(7,7) = (7*2+1)+(7*2+1)*17 = 15+15*17 = 15+255 = 270
      expect(QuoridorEngine.wallBaseId(7, 7), 270);
      // wallBaseId(3,4) = (3*2+1)+(4*2+1)*17 = 7+153 = 160
      expect(QuoridorEngine.wallBaseId(3, 4), 160);
    });

    test('wallOccupiedCells 横墙 (3,4) = [159, 160, 161]', () {
      final cells = QuoridorEngine.wallOccupiedCells(3, 4, WallOrientation.horizontal);
      expect(cells, [159, 160, 161], reason: 'base=160, horizontal=[-1, 0, +1]');
    });

    test('wallOccupiedCells 竖墙 (3,4) = [143, 160, 177]', () {
      final cells = QuoridorEngine.wallOccupiedCells(3, 4, WallOrientation.vertical);
      expect(cells, [143, 160, 177], reason: 'base=160, vertical=[-17, 0, +17]');
    });
  });

  group('走棋', () {
    test('top 向下走 (4→13) → topPlayerId 更新', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.movePiece(state, 13)!;
      expect(state.topPlayerId, 13, reason: 'top 向下走一步');
      // 不触发自动换手（currentPlayerIsTop 不变）
      expect(state.currentPlayerIsTop, true);
    });

    test('top 走到无效格子 → 返回 null', () {
      final state = QuoridorEngine.initialize();
      final result = QuoridorEngine.movePiece(state, 76); // bottom 位置，无效
      expect(result, isNull);
    });

    test('走棋后 history 长度 +1', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.movePiece(state, 13)!;
      expect(state.history.length, 1);
      expect(state.history[0].isWall, false);
      expect(state.history[0].isTopPlayer, true);
    });

    test('走棋后不自动换手', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.movePiece(state, 13)!;
      expect(state.currentPlayerIsTop, true,
          reason: 'movePiece 不翻转 currentPlayerIsTop');
    });
  });

  group('跳跃', () {
    test('top (4,3), bottom (4,4) → validMoves 含 (4,5)', () {
      // 构造：top 在 cellId=31(x=4,y=3), bottom 在 cellId=40(x=4,y=4)
      // top 的邻接包含 40(=bottom), 应跳过到底线侧 cellId=49(x=4,y=5)
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 31,
        bottomPlayerId: 40,
        currentPlayerIsTop: true,
      );
      final topMoves = QuoridorEngine.getValidMoves(
        state.adjacency, 31, 40,
      );
      expect(topMoves.contains(49), true,
          reason: 'top 应跳过 bottom 到 (4,5)=49');
    });

    test('top (4,3), bottom 不相邻 → 仅四邻接', () {
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 31,
        bottomPlayerId: 76,
        currentPlayerIsTop: true,
      );
      final topMoves = QuoridorEngine.getValidMoves(
        state.adjacency, 31, 76,
      );

      // 不相邻，正确移动
      // top 在 31(y=3)，邻接 30(left), 32(right), 22(up), 40(down)
      // 没有跳跃
      expect(topMoves.length, 4, reason: '无跳跃时四格可走');
      expect(topMoves, containsAll([30, 32, 22, 40]));
    });
  });

  group('换手', () {
    test('switchTurn 翻转 currentPlayerIsTop 并重算 validMoves', () {
      var state = QuoridorEngine.initialize();
      // 初始 currentPlayerIsTop=true (top)
      // top 的 validMoves 包含 13(down), 3(left), 5(right)
      state = QuoridorEngine.switchTurn(state);

      expect(state.currentPlayerIsTop, false, reason: '翻转为 bottom 回合');
      expect(state.validMoves, isNotEmpty, reason: 'bottom 也有可走格');
      // bottom 在 cellId=76(y=8), 可走上、左、右
      // bottom 的邻接: 67(up), 75(left), 77(right)
    });

    test('switchTurn 不修改棋子位置和墙壁数', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.switchTurn(state);

      expect(state.topPlayerId, 4);
      expect(state.bottomPlayerId, 76);
      expect(state.topWallsPlaced, 0);
      expect(state.bottomWallsPlaced, 0);
    });
  });

  group('邻接表更新', () {
    test('横墙 (0,0) → 切断 (0,9) 和 (1,10)', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      final result = QuoridorEngine.applyWallToAdjacency(
        adj, 0, 0, WallOrientation.horizontal, true,
      );
      expect(result[0].contains(9), false, reason: '0→9 切断');
      expect(result[9].contains(0), false, reason: '9→0 切断');
      expect(result[1].contains(10), false, reason: '1→10 切断');
      expect(result[10].contains(1), false, reason: '10→1 切断');
      // 没有意外切断
      expect(result[0].contains(1), true, reason: '0→1 仍在');
    });

    test('竖墙 (0,0) → 切断 (0,1) 和 (9,10)', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      final result = QuoridorEngine.applyWallToAdjacency(
        adj, 0, 0, WallOrientation.vertical, true,
      );
      expect(result[0].contains(1), false, reason: '0→1 切断');
      expect(result[1].contains(0), false, reason: '1→0 切断');
      expect(result[9].contains(10), false, reason: '9→10 切断');
      expect(result[10].contains(9), false, reason: '10→9 切断');
      // 没有意外切断
      expect(result[0].contains(9), true, reason: '0→9 仍在');
    });

    test('applyWallToAdjacency isPlacing=false → 完美恢复', () {
      final adj = QuoridorEngine.buildInitialAdjacency();
      final cut = QuoridorEngine.applyWallToAdjacency(
        adj, 3, 4, WallOrientation.horizontal, true,
      );
      final restored = QuoridorEngine.applyWallToAdjacency(
        cut, 3, 4, WallOrientation.horizontal, false,
      );
      // 和原始比较
      for (int i = 0; i < 81; i++) {
        expect(restored[i], adj[i], reason: 'node $i 恢复一致');
      }
    });
  });
}
```

- [ ] **Step 5: 运行所有单测试**

```bash
flutter test test/core/surround_game/game_state_test.dart test/core/surround_game/bfs_pathfinder_test.dart test/core/surround_game/game_engine_test.dart -v
```

Expected: (P2 6 + P3 10 + P4a 15 + P3 extra 1 fromBoardSpec) = 32 tests all PASS.

如果某个 fail，逐条调试。注意 `bothPlayersHavePath` 测试可能需要根据实际情况调整辅组函数。

- [ ] **Step 6: flutter analyze**

```bash
flutter analyze
```

Expected: 0 errors.

- [ ] **Step 7: Commit**

```bash
git add lib/core/surround_game/engine/game_engine.dart lib/core/surround_game/surround_game.dart test/core/surround_game/game_engine_test.dart test/core/surround_game/game_state_test.dart
git commit -m "feat(surround_game): QuoridorEngine 走棋+跳跃+换手 (含单测 16 用例)"
```

---

## Task 6: P4b — QuoridorEngine 放墙 + 胜负 + 单测增量

**Files:**
- Modify: `lib/core/surround_game/engine/game_engine.dart`（追加放墙+胜负 — 已在 Task 5 的完整实现中包含? 是的，上述完整代码已包含全部方法）
- Just verify everything's there and add the remaining tests.

- [ ] **Step 1: 补 game_engine_test.dart — 放墙 + 胜负（11 用例）**

在 `game_engine_test.dart` 末尾追加：

```dart
  // ═══════════════════════════════════════════════════════
  // 以下在 P4b 阶段追加
  // ═══════════════════════════════════════════════════════

  group('放墙', () {
    test('空棋盘横墙 (3,4) → 合法：wallGrid 三格占用', () {
      final state = QuoridorEngine.initialize();
      final result = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal);
      expect(result, isNotNull);
      expect(result!.wallGrid[159], true, reason: 'base=160, 左格');
      expect(result.wallGrid[160], true, reason: '中心格');
      expect(result.wallGrid[161], true, reason: '右格');
    });

    test('同位置再放 → 重叠不合法 → null', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal)!;
      final result = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal);
      expect(result, isNull, reason: '墙壁重叠非法');
    });

    test('横墙叉竖墙（共享中心格 160）→ 不合法', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal)!;
      // 竖墙 (3,4) 也占用 160
      final result = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.vertical);
      expect(result, isNull, reason: '共享中心格 160');
    });

    test('把 top 完全封死 → 不合法', () {
      var state = QuoridorEngine.initialize();
      // 在 y=0 放 4 块横墙阻断 top 向下所有出路
      // top 在 cellId=4(x=4,y=0)
      // 横墙 (0,0)(2,0)(4,0)(6,0)
      state = QuoridorEngine.placeWall(state, 0, 0, WallOrientation.horizontal)!;
      state = QuoridorEngine.placeWall(state, 2, 0, WallOrientation.horizontal)!;
      state = QuoridorEngine.placeWall(state, 4, 0, WallOrientation.horizontal)!;
      // 第 4 块墙应该检测到 top 被封死
      final result = QuoridorEngine.placeWall(state, 6, 0, WallOrientation.horizontal);
      expect(result, isNull, reason: 'top 被封死不能放');
    });

    test('放墙后 topWallsPlaced +1', () {
      var state = QuoridorEngine.initialize();
      state = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal)!;
      expect(state.topWallsPlaced, 1, reason: 'top 放了第一块墙');
    });

    test('wallCountPerPlayer 用尽后再放 → null', () {
      var state = QuoridorEngine.initialize();
      // 模拟 top 已放置 10 面墙
      state = state.copyWith(topWallsPlaced: 10);
      final result = QuoridorEngine.placeWall(state, 3, 4, WallOrientation.horizontal);
      expect(result, isNull, reason: '墙数用尽');
    });

    test('坐标越界 (8,0) horizontal → null（修正 Swift bug）', () {
      final state = QuoridorEngine.initialize();
      final result = QuoridorEngine.placeWall(
        state, 8, 0, WallOrientation.horizontal,
      );
      expect(result, isNull, reason: 'x=8 超出 [0,7] 范围');
    });
  });

  group('胜负', () {
    test('top 走到 y=8 → checkStatus = topWin', () {
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 76, // x=4,y=8 已到达底线
        bottomPlayerId: 4,
        currentPlayerIsTop: true,
      );
      final status = QuoridorEngine.checkStatus(
        state.adjacency, 76, 4,
      );
      expect(status, GameStatus.topWin);
    });

    test('bottom 走到 y=0 → checkStatus = bottomWin', () {
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 76,
        bottomPlayerId: 4, // x=4,y=0 已到达底线
        currentPlayerIsTop: false,
      );
      final status = QuoridorEngine.checkStatus(
        state.adjacency, 76, 4,
      );
      expect(status, GameStatus.bottomWin);
    });

    test('top 和 bottom 都在底线 → draw', () {
      // Swift checkStatus 逻辑：
      //   if topPlayer.y == 8 {
      //     if GameAi.pathForPlayer(false).count == 1 { return .Draw }
      //     return .TopWin
      //   }
      // path.length==1 意味着起点就是终点（已在目标行）
      // 所以 top.y==8 且 bottom.y==0 → 进入第一支，bottom path=[0] length=1 → Draw
      final state = QuoridorEngine.fromBoardSpec(
        topPlayerId: 72, // x=0,y=8
        bottomPlayerId: 0, // x=0,y=0
        currentPlayerIsTop: true,
      );
      final status = QuoridorEngine.checkStatus(
        state.adjacency, 72, 0,
      );
      expect(status, GameStatus.draw,
          reason: 'top 在 y=8, bottom 在 y=0 → draw');
    });

    test('普通状态 → running', () {
      final state = QuoridorEngine.initialize();
      final status = QuoridorEngine.checkStatus(
        state.adjacency, 4, 76,
      );
      expect(status, GameStatus.running);
    });
  });
```

- [ ] **Step 2: 运行全部测试**

```bash
flutter test test/core/surround_game/ -v
```

Expected: (P2 6 + P3 10 + P4a 15 + P4a fromBoardSpec 1 + P4b 11) = 43 用例全 PASS。

如果某些 fail 调试修正。

- [ ] **Step 3: flutter analyze**

```bash
flutter analyze
```

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add test/core/surround_game/game_engine_test.dart
git commit -m "feat(surround_game): QuoridorEngine 放墙+胜负 (含单测 11 用例)"
```

---

## Task 7: P5 — Service / Lobby noop 收尾

**Files:**
- Modify: `lib/core/surround_game/surround_game_service.dart`
- Modify: `lib/core/surround_game/surround_game.dart`（检查导出已经完善）
- Verify: `flutter analyze` + `flutter test`

- [ ] **Step 1: surround_game_service.dart — 修整**

检查当前 `surround_game_service.dart`，确保：
1. `import 'engine/game_engine.dart'` 已删除（P0 时做的）
2. `executeMove` 方法已删除（P0 时做的）
3. `_handleGameSync` 和 `_handleGameInput` 改为 noop

从当前的 service.dart 看，`_handleGameSync` 和 `_handleGameInput` 仍然引用旧的 `GameState`。由于 `models/game_state.dart` 已被重写，这些方法可能会编译失败。

修改这两个 handler：

```dart
  /// 处理游戏状态同步（noop — 下轮 LAN 同步重做）
  Future<void> _handleGameSync(HttpRequest request) async {
    debugPrint('[SurroundGame] sync 收到（noop）');
    request.response.write('OK');
    await request.response.close();
  }

  /// 处理玩家输入（noop — 下轮 LAN 同步重做）
  Future<void> _handleGameInput(HttpRequest request) async {
    debugPrint('[SurroundGame] input 收到（noop）');
    request.response.write('OK');
    await request.response.close();
  }
```

同时检查 `currentGameState` 的引用：
- `_currentGameState` 是 `GameState?` 类型（新的 GameState），但旧的 getter/setter 与新 GameState 不兼容 — 确实不匹配，因为旧 `GameState` 已经移到 `_legacy/`
- 新 `GameState` 的定义与旧完全不同
- 需要删除 `_currentGameState` 字段和相关的 `currentGameState` getter

找到：
```dart
  /// 当前游戏状态
  GameState? _currentGameState;
  GameState? get currentGameState => _currentGameState;
```

删除这些行。

同时删除 `startGame()` 方法（它在 P0 时引用了旧 `GameEngine.initialize()`）：

```dart
  /// 开始游戏（仅 Host 调用）
  GameState startGame() {
    final state = GameEngine.initialize();
    _currentGameState = state;
    _gameStateController.add(state);
    debugPrint('[SurroundGame] 游戏开始');
    return state;
  }
```

- [ ] **Step 2: surround_game.dart — 确认导出完整**

当前 `surround_game.dart` 已导出（从之前的 task）：
```dart
export 'surround_game_constants.dart';
export 'models/game_room.dart';
export 'models/player_input.dart';
export 'models/game_state.dart';
export 'models/game_event.dart';
export 'engine/bfs_pathfinder.dart';
export 'engine/game_engine.dart';
export 'surround_game_service.dart';
export 'pages/game_lobby_page.dart';
export 'pages/game_room_page.dart';
export 'widgets/room_list_tile.dart';
```

检查是否有遗漏的 `room_list_tile.dart` — 当前已包含。

- [ ] **Step 3: flutter analyze**

```bash
flutter analyze
```

Expected: 0 errors.

如果 _legacy/ 产生 warning，`analysis_options.yaml` 中加：
```yaml
analyzer:
  exclude:
    - "lib/core/surround_game/_legacy/**"
```

- [ ] **Step 4: 运行全部测试**

```bash
flutter test test/core/surround_game/ -v
```

Expected: ~43 用例全 PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/core/surround_game/surround_game_service.dart lib/core/surround_game/surround_game.dart
git commit -m "chore(surround_game): Service 收尾 + 导出对齐"
```

---

## Task 8: P6 — 验证 + 文档

**Files:**
- Modify: `docs/围追堵截-Quoridor任务清单.md`
- Modify: `docs/围追堵截-Quoridor重写执行文档.md`

- [ ] **Step 1: 启动 app 基本验证**

```bash
flutter run
```

在模拟器/真机上验证：
1. 进入"围追堵截"大厅 → 能正常显示房间列表
2. 点"本地对战" → 看到 PlaceholderPage("Quoridor 重写中")
3. 返回大厅，点右上角 + → 创建房间 → 看到 PlaceholderPage
4. UDP 多设备发现仍工作（与另一设备/模拟器同时在线，都能看到彼此的房间）

- [ ] **Step 2: 更新任务清单**

在 `docs/围追堵截-Quoridor任务清单.md` 顶部追加：

```markdown
> ## ✅ 已完成：Phase 1 — 引擎重写
>
> | 阶段 | 状态 | Commit |
> |------|------|--------|
> | P0 整理 _legacy/ | ✅ | — |
> | P1 常量+枚举 | ✅ | — |
> | P2 GameState+MoveRecord+Event | ✅ | — |
> | P3 BFS pathfinder | ✅ | — |
> | P4a 引擎走棋+跳跃+换手 | ✅ | — |
> | P4b 引擎放墙+胜负 | ✅ | — |
> | P5 Service noop 收尾 | ✅ | — |
> | P6 验证+文档 | ✅ | — |
>
> **合计 ~43 单测，全部通过。下轮期待：Quoridor UI 重写。**
>
> ---
```

- [ ] **Step 3: 更新重写执行文档**

在 `docs/围追堵截-Quoridor重写执行文档.md` 每个章节后追加 ✅ 标记或在顶部加注释：

```markdown
> 实施状态：Phase 1（引擎层）已全部完成。见 `docs/superpowers/specs/2026-06-12-quoridor-engine-rewrite-design.md`。
```

- [ ] **Step 4: Commit**

```bash
git add docs/围追堵截-Quoridor任务清单.md docs/围追堵截-Quoridor重写执行文档.md
git commit -m "docs(surround_game): Phase 1 引擎完成标记"
```

---

## 附录 A: 关键算法参考

### A.1 棋盘编码

```
9×9 棋格（cellId = x + y*9, 0-80）:
    0   1   2   3   4   5   6   7   8       ← y=0 (bottom 目标行)
    9  10  11  12  13  14  15  16  17       ← y=1
    ...
   72  73  74  75  76  77  78  79  80       ← y=8 (top 目标行)

17×17 墙壁网格（wallGridId）:
   每个棋格之间的"缝隙"有 1 个 wallGrid 单元。
   坐标 (x*2+1, y*2+1) 是棋格 (x,y) 周围的墙壁格子中心。
   wallGridId = (x*2+1) + (y*2+1)*17
   横向墙：占 3 个连续的水平格子 [baseId-1, baseId, baseId+1]
   竖向墙：占 3 个连续的竖直格子 [baseId-17, baseId, baseId+17]
```

### A.2 邻接切断（Swift removeNearLink 翻译）

横墙位置 (x,y)，棋格坐标：
```
baseId = x + y * 9  (棋格坐标)
切断：
  (baseId, baseId+9)       — 横墙上方棋格到下方棋格
  (baseId+1, baseId+10)    — 横墙上方右侧棋格到下方右侧棋格
```

竖墙位置 (x,y)：
```
baseId = x + y * 9
切断：
  (baseId, baseId+1)       — 竖墙左方棋格到右方棋格
  (baseId+9, baseId+10)    — 竖墙下方棋格到右下方棋格
```

### A.3 Swift DataModel 字段映射

| Swift | Dart | 举例 |
|-------|------|------|
| `DataModel.x` | 走棋时的 `cellId % 9`；放墙时的 `x` | 0-8 |
| `DataModel.y` | 走棋时的 `cellId ~/ 9`；放墙时的 `y` | 0-8 |
| `DataModel.h` | 走棋时的 `isTopPlayer`；放墙时 `orientation == horizontal` | true/false |
| `DataModel.t` | `isWall` | false=棋, true=墙 |
| `DataModel.id` | `x + y * 9`（仅在走棋/邻接切断时有用） | 0-80 |
| `DataModel.wallIds` | `wallOccupiedCells()` 返回值 | [base-1,base,base+1] etc |
