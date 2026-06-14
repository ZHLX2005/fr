# 围追堵截 (Quoridor) 回放系统 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 一局结束后可在只读棋盘上逐手回看，支持播放/暂停/步进/拖动/变速；并补齐引擎缺失的 `replayHistory` 重建原语。

**Architecture:** 引擎层新增信任棋谱的几何重建原语 `applyMoveRecord` / `replayHistory`（步退即"从零重建到光标"，无逆操作）；独立的 `ReplayController`（`ValueNotifier` + `Timer.periodic` 自动播放）驱动只读 `ReplayPage`（复用现有棋盘 widget）。`fromJson` 保持 raw（方案 A，model 不依赖 engine），由调用方显式 `replayHistory`。

**Tech Stack:** Dart / Flutter，`flutter_test`，`package:fake_async`（`flutter_test` 传递依赖，无需改 pubspec）。

**关联 spec：** `docs/superpowers/specs/2026-06-13-surround-game-replay-design.md`

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/core/surround_game/engine/game_engine.dart` | 修改 | 新增 `applyMoveRecord` / `replayHistory` / `_recomputeTurn`；`switchTurn` 重构为委托 |
| `lib/core/surround_game/models/game_state.dart` | 修改 | 更新 `toJson`/`fromJson` 注释（方案 A：调用方 replayHistory） |
| `lib/core/surround_game/replay/replay_controller.dart` | 新建 | `ReplaySpeed` / `ReplayState` / `ReplayController` |
| `lib/core/surround_game/pages/replay_page.dart` | 新建 | 只读回放页 + 传输条 |
| `lib/core/surround_game/pages/game_page.dart` | 修改 | 胜利弹层加「观看回放」按钮 |
| `lib/core/surround_game/surround_game.dart` | 修改 | 导出新文件 |
| `test/core/surround_game/_fixtures.dart` | 新建 | 确定性合法混合对局 fixture |
| `test/core/surround_game/game_engine_test.dart` | 修改 | 新增 `group('replay')` |
| `test/core/surround_game/game_state_test.dart` | 不变 | （fromJson 往返已有；本轮复用） |
| `test/core/surround_game/replay_controller_test.dart` | 新建 | 控制器单测（含 fake_async） |
| `test/core/surround_game/replay_page_test.dart` | 新建 | widget smoke |

测试命令统一：`flutter test test/core/surround_game/`（单文件：替换路径）。分析：`flutter analyze lib/core/surround_game test/core/surround_game`。

---

## Task 1: 引擎 `applyMoveRecord`（信任棋谱的几何重建）

**Files:**
- Modify: `lib/core/surround_game/engine/game_engine.dart`（在 `placeWall` 之后、`isWallPlacementValid` 之前新增方法）
- Test: `test/core/surround_game/game_engine_test.dart`（新增 `group('applyMoveRecord')`）

- [ ] **Step 1: 写失败测试** —— 在 `game_engine_test.dart` 的 `main()` 内（任意已有 group 之后）追加：

```dart
  group('applyMoveRecord', () {
    test('走棋 → 移动方 cellId 更新、history +1', () {
      var s = QuoridorEngine.initialize();
      // top 走到 cellId 13（初始 validMoves 含 13）
      s = QuoridorEngine.applyMoveRecord(
        s, MoveRecord.move(cellId: 13, isTopPlayer: true));
      expect(s.topPlayerId, 13, reason: 'top 应移到 13');
      expect(s.bottomPlayerId, 76, reason: 'bottom 不动');
      expect(s.history.length, 1);
      expect(s.history.last.isWall, false);
    });

    test('放墙 → wallGrid 3 格 true、邻接切断、计数 +1', () {
      var s = QuoridorEngine.initialize();
      s = QuoridorEngine.applyMoveRecord(
        s, MoveRecord.wall(x: 3, y: 4, orientation: WallOrientation.horizontal, isTopPlayer: true));
      // wallBaseId(3,4)=160 → horizontal 占 [159,160,161]
      expect(s.wallGrid[159], true);
      expect(s.wallGrid[160], true);
      expect(s.wallGrid[161], true);
      // 邻接切断 (39,48) 与 (40,49)
      expect(s.adjacency[39].contains(48), false);
      expect(s.adjacency[40].contains(49), false);
      expect(s.topWallsPlaced, 1);
      expect(s.bottomWallsPlaced, 0);
      expect(s.history.length, 1);
    });

    test('按 record.isTopPlayer 应用，不看 state.currentPlayerIsTop', () {
      // 故意把 state 的回合设成 bottom，但 record 声明 top
      var s = QuoridorEngine.initialize().copyWith(currentPlayerIsTop: false);
      s = QuoridorEngine.applyMoveRecord(
        s, MoveRecord.move(cellId: 13, isTopPlayer: true));
      expect(s.topPlayerId, 13, reason: 'record 说是 top，就动 top');
      expect(s.currentPlayerIsTop, false, reason: 'applyMoveRecord 不翻回合');
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/surround_game/game_engine_test.dart`
Expected: 编译失败 —— `QuoridorEngine.applyMoveRecord` 未定义。

- [ ] **Step 3: 实现 `applyMoveRecord`** —— 在 `game_engine.dart` 的 `placeWall` 方法之后（`// ═══════════════════════ 墙壁合法性校验 ═══════════════════════` 注释之前）插入：

```dart
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/surround_game/game_engine_test.dart`
Expected: PASS（含新增 3 个 `applyMoveRecord` 用例 + 既有全部用例）。

- [ ] **Step 5: Commit**

```bash
git add lib/core/surround_game/engine/game_engine.dart test/core/surround_game/game_engine_test.dart
git commit -m "feat(surround_game): 引擎 applyMoveRecord 信任棋谱几何重建 (单测 3)"
```

---

## Task 2: 引擎 `replayHistory` + `switchTurn` 重构 + 核心"replay≡live"不变量

**Files:**
- Modify: `lib/core/surround_game/engine/game_engine.dart`（重构 `switchTurn`、新增 `_recomputeTurn` + `replayHistory`）
- Create: `test/core/surround_game/_fixtures.dart`
- Test: `test/core/surround_game/game_engine_test.dart`（新增 `group('replay')`）

- [ ] **Step 1: 写测试 fixture** —— 新建 `test/core/surround_game/_fixtures.dart`：

```dart
// 确定性的合法混合对局（走 + 墙），供 replay 不变量 / 控制器 / widget smoke 复用。
//
// 不手写具体落子（避免非法），而是在第 i 手用确定性策略选合法动作：
//   - 走棋回合：取 validMoves 中最小 cellId
//   - 第 2、5 手：放第一面合法墙
// 遇终局即停。返回 (finalHistory, 每手 switchTurn 后的快照)。
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';

/// 第一个合法墙（从 (0,0) 起扫，横/竖各试）；无则返回 null。
GameState? _firstLegalWall(GameState s) {
  for (var x = 0; x <= 7; x++) {
    for (var y = 0; y <= 7; y++) {
      for (final o in WallOrientation.values) {
        if (QuoridorEngine.isWallPlacementValid(
              s.wallGrid, s.adjacency, s.topPlayerId, s.bottomPlayerId, x, y, o)) {
          return QuoridorEngine.placeWall(s, x, y, o);
        }
      }
    }
  }
  return null;
}

/// 混合对局：history 为完整棋谱；snapshots[k] = 第 (k+1) 手 switchTurn 后的 GameState。
({List<MoveRecord> history, List<GameState> snapshots}) buildMixedGame() {
  var state = QuoridorEngine.initialize();
  final snapshots = <GameState>[];
  const maxMoves = 8;
  for (var i = 0; i < maxMoves; i++) {
    if (state.status != GameStatus.running) break; // 终局停
    if (state.validMoves.isEmpty) break; // 极端边界：无路可走则停
    final GameState next;
    if (i == 2 || i == 5) {
      next = _firstLegalWall(state) ?? state; // 无合法墙则退化为不前进
      if (next == state) break;
    } else {
      final target = state.validMoves.reduce(min);
      next = QuoridorEngine.movePiece(state, target)!;
    }
    state = QuoridorEngine.switchTurn(next);
    snapshots.add(state);
  }
  return (history: state.history, snapshots: snapshots);
}

int min(int a, int b) => a < b ? a : b;
```

> 注：`Set.reduce` 要求集合非空；`state.validMoves` 在 `running` 时非空（活玩家总有路）。若担心，可加 `if (state.validMoves.isEmpty) break;` 在循环顶部。Step 1 最终版请在 `for` 内 `i==2||i==5` 分支前补一行 `if (state.validMoves.isEmpty) break;`。

- [ ] **Step 2: 写失败测试** —— 在 `game_engine_test.dart` 文件顶部加 import：

```dart
import 'dart:math' show unorderedEquals;
import '_fixtures.dart';
```

> `unorderedEquals` 来自 `package:matcher`，由 `flutter_test` 再导出，无需额外依赖。

在 `main()` 内追加（紧跟 `group('applyMoveRecord')` 之后）：

```dart
  group('replay', () {
    test('replayHistory([]) == initialize()', () {
      final r = QuoridorEngine.replayHistory(const []);
      final init = QuoridorEngine.initialize();
      expect(r.topPlayerId, init.topPlayerId);
      expect(r.bottomPlayerId, init.bottomPlayerId);
      expect(r.currentPlayerIsTop, true);
      expect(r.status, GameStatus.running);
      expect(r.wallGrid, equals(init.wallGrid));
    });

    test('upTo clamp：<0 → 0，>length → length', () {
      final game = buildMixedGame();
      final n = game.history.length;
      expect(QuoridorEngine.replayHistory(game.history, upTo: -3).topPlayerId,
             QuoridorEngine.replayHistory(game.history, upTo: 0).topPlayerId,
             reason: 'upTo<0 等价 upTo=0');
      expect(QuoridorEngine.replayHistory(game.history, upTo: n + 5).history.length, n,
             reason: 'upTo>length 钳到 length');
    });

    test('replay ≡ live：逐手快照与 replayHistory(upTo:k) 完全一致', () {
      final game = buildMixedGame();
      expect(game.snapshots, isNotEmpty, reason: 'fixture 应产出至少 1 手');
      for (var k = 0; k < game.snapshots.length; k++) {
        final snap = game.snapshots[k];
        final replayed = QuoridorEngine.replayHistory(game.history, upTo: k + 1);
        expect(replayed.topPlayerId, snap.topPlayerId, reason: 'move ${k + 1} topId');
        expect(replayed.bottomPlayerId, snap.bottomPlayerId, reason: 'move ${k + 1} botId');
        expect(replayed.topWallsPlaced, snap.topWallsPlaced, reason: 'move ${k + 1} topWalls');
        expect(replayed.bottomWallsPlaced, snap.bottomWallsPlaced, reason: 'move ${k + 1} botWalls');
        expect(replayed.currentPlayerIsTop, snap.currentPlayerIsTop, reason: 'move ${k + 1} turn');
        expect(replayed.status, snap.status, reason: 'move ${k + 1} status');
        expect(replayed.validMoves, unorderedEquals(snap.validMoves), reason: 'move ${k + 1} validMoves');
        expect(replayed.wallGrid, equals(snap.wallGrid), reason: 'move ${k + 1} wallGrid');
        expect(replayed.history.length, snap.history.length, reason: 'move ${k + 1} history len');
        for (var i = 0; i < 81; i++) {
          expect(replayed.adjacency[i], unorderedEquals(snap.adjacency[i]),
              reason: 'move ${k + 1} adjacency[$i]');
        }
      }
    });

    test('回放后回合：currentPlayerIsTop = !history[k-1].isTopPlayer', () {
      final game = buildMixedGame();
      // k=0 → top 先手
      expect(QuoridorEngine.replayHistory(game.history, upTo: 0).currentPlayerIsTop, true);
      // k≥1 → 与最后一手相反
      for (var k = 1; k <= game.history.length; k++) {
        final lastTop = game.history[k - 1].isTopPlayer;
        expect(QuoridorEngine.replayHistory(game.history, upTo: k).currentPlayerIsTop,
               !lastTop, reason: 'upTo=$k');
      }
    });

    test('fromJson + 调用方 replayHistory 闭环 → adjacency/wallGrid 复现', () {
      final game = buildMixedGame();
      final finalState = game.snapshots.last;
      final decoded = GameState.fromJson(finalState.toJson());
      // fromJson 后 adjacency/wallGrid 仍空（方案 A）→ 调用方显式 replayHistory
      expect(decoded.adjacency.every((s) => s.isEmpty), true, reason: 'fromJson 不重建 adjacency');
      final rebuilt = QuoridorEngine.replayHistory(decoded.history);
      expect(rebuilt.topPlayerId, finalState.topPlayerId);
      expect(rebuilt.bottomPlayerId, finalState.bottomPlayerId);
      expect(rebuilt.wallGrid, equals(finalState.wallGrid));
      for (var i = 0; i < 81; i++) {
        expect(rebuilt.adjacency[i], unorderedEquals(finalState.adjacency[i]));
      }
    });
  });
```

- [ ] **Step 3: 跑测试确认失败**

Run: `flutter test test/core/surround_game/game_engine_test.dart`
Expected: FAIL —— `QuoridorEngine.replayHistory` 未定义。

- [ ] **Step 4: 重构 `switchTurn` + 新增 `_recomputeTurn` + `replayHistory`**

把现有 `switchTurn`（即 `game_engine.dart` 中 `static GameState switchTurn(GameState state) {...}` 整段）替换为：

```dart
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
  static GameState switchTurn(GameState state) =>
      _recomputeTurn(state, !state.currentPlayerIsTop);
```

在 `applyMoveRecord` 之后新增 `replayHistory`：

```dart
  /// 从棋谱 [history] 重建完整 GameState（信任棋谱、仅几何）。
  ///
  /// [upTo] = 光标（已应用步数）：0=开局、length=终局；缺省=全量。越界自动 clamp。
  /// 步退无需逆操作：cursor 10→5 只需 `replayHistory(h, upTo: 5)`。
  ///
  /// 流程：initialize() → 逐条 applyMoveRecord → 末尾 [_recomputeTurn] 重算回合/可走/状态。
  /// 回合派生自最后一手：n=0 → top 先手；否则 = !history[n-1].isTopPlayer。
  static GameState replayHistory(List<MoveRecord> history, {int? upTo}) {
    final n = upTo == null ? history.length : upTo.clamp(0, history.length) as int;
    var state = initialize();
    for (var i = 0; i < n; i++) {
      state = applyMoveRecord(state, history[i]);
    }
    final isTop = (n == 0) ? true : !history[n - 1].isTopPlayer;
    return _recomputeTurn(state, isTop);
  }
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/core/surround_game/`
Expected: PASS（含 `applyMoveRecord` 3 + `replay` 5，及既有全部用例；核心 `replay ≡ live` 必须绿）。

- [ ] **Step 6: Commit**

```bash
git add lib/core/surround_game/engine/game_engine.dart test/core/surround_game/game_engine_test.dart test/core/surround_game/_fixtures.dart
git commit -m "feat(surround_game): 引擎 replayHistory 重建原语 + switchTurn 重构 (单测 5, 含 replay≡live)"
```

---

## Task 3: `fromJson` 注释更新（方案 A，关闭已知局限）

**Files:**
- Modify: `lib/core/surround_game/models/game_state.dart`（`toJson` 与 `fromJson` 的文档注释）

- [ ] **Step 1: 更新 `toJson` 注释** —— 把 `toJson` 内这段：

```dart
        // 注意：adjacency 和 wallGrid 不序列化（由 QuoridorEngine 从
        // history 重放重建）。validMoves 序列化作为 hints。
        // 如果需要 full state 远程重建，需要序列化 wallGrid。
        // 下轮 LAN 同步时补充。
```

替换为：

```dart
        // 注意：adjacency 和 wallGrid 不序列化。反序列化后由调用方
        // 调用 QuoridorEngine.replayHistory(history) 重建（见 fromJson 注释）。
        // validMoves 序列化作为 hints；权威值由 replayHistory 重算。
```

- [ ] **Step 2: 更新 `fromJson` 注释** —— 把 `fromJson` 上方这段：

```dart
  /// 反序列化
  ///
  /// 注意：deserialize 后的 state **不保证** adjacency 和 wallGrid 正确。
  /// 上轮要用 QuoridorEngine.replayHistory(history) 重建。
  /// 这局限将在下轮 LAN 同步时解决。
```

替换为：

```dart
  /// 反序列化
  ///
  /// **调用方须知（方案 A，保持 model 不依赖 engine）**：
  /// 反序列化后 adjacency/wallGrid 为空、validMoves 仅为 hint。
  /// 需要完整可玩状态时，由调用方显式调用：
  ///   `QuoridorEngine.replayHistory(state.history)`
  /// 重建 adjacency/wallGrid/validMoves/status。replayHistory 已在引擎层就绪。
```

- [ ] **Step 3: 跑测试确认无回归**

Run: `flutter test test/core/surround_game/`
Expected: PASS（fromJson 往返既有用例 + Task 2 的 fromJson 闭环用例都绿）。

- [ ] **Step 4: Commit**

```bash
git add lib/core/surround_game/models/game_state.dart
git commit -m "docs(surround_game): fromJson 注释更新为方案 A（调用方 replayHistory 重建）"
```

---

## Task 4: `ReplayState` + `ReplaySpeed`（不可变值对象）

**Files:**
- Create: `lib/core/surround_game/replay/replay_controller.dart`（先放枚举 + 状态类；控制器在 Task 5/6 追加到同文件）

- [ ] **Step 1: 写失败测试** —— 新建 `test/core/surround_game/replay_controller_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/replay/replay_controller.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';
import '_fixtures.dart';

void main() {
  group('ReplayState.initial', () {
    test('cursor=0 / !isPlaying / x1 / board==开局', () {
      final game = buildMixedGame();
      final c = ReplayController(history: game.history);
      expect(c.state.cursor, 0);
      expect(c.state.isPlaying, false);
      expect(c.state.speed, ReplaySpeed.x1);
      expect(c.state.totalMoves, game.history.length);
      expect(c.state.atStart, true);
      expect(c.state.atEnd, game.history.isEmpty);
      expect(c.state.board.topPlayerId, SurroundGameConstants.topPlayerStart);
      expect(c.state.board.bottomPlayerId, SurroundGameConstants.bottomPlayerStart);
      c.dispose();
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/surround_game/replay_controller_test.dart`
Expected: FAIL —— `ReplayController` 未定义。

- [ ] **Step 3: 实现枚举 + 状态类 + 控制器骨架** —— 新建 `lib/core/surround_game/replay/replay_controller.dart`：

```dart
import 'dart:async';
import 'dart:math' show min, max;

import 'package:flutter/foundation.dart';

import '../engine/game_engine.dart';
import '../models/game_state.dart';

/// 自动播放基准间隔（@1x）。@2x/@4x 按倍率缩短。
const Duration kReplayBaseInterval = Duration(milliseconds: 800);

/// 回放速度倍率。
enum ReplaySpeed { x1, x2, x4 }

Duration _intervalFor(ReplaySpeed s) {
  switch (s) {
    case ReplaySpeed.x1:
      return kReplayBaseInterval;
    case ReplaySpeed.x2:
      return kReplayBaseInterval ~/ 2;
    case ReplaySpeed.x4:
      return kReplayBaseInterval ~/ 4;
  }
}

/// 回放视图状态（不可变）。[board] 为光标处的完整棋盘快照。
class ReplayState {
  final List<MoveRecord> history;
  final int cursor; // 0..history.length
  final ReplaySpeed speed;
  final bool isPlaying;
  final GameState board;

  const ReplayState({
    required this.history,
    required this.cursor,
    required this.speed,
    required this.isPlaying,
    required this.board,
  });

  int get totalMoves => history.length;
  bool get atStart => cursor == 0;
  bool get atEnd => cursor >= history.length;

  factory ReplayState.initial(List<MoveRecord> history) => ReplayState(
        history: List.unmodifiable(List.of(history)),
        cursor: 0,
        speed: ReplaySpeed.x1,
        isPlaying: false,
        board: QuoridorEngine.replayHistory(history, upTo: 0),
      );
}

/// 回放控制器 —— 驱动 [ValueNotifier<ReplayState>]，提供传输控件。
class ReplayController {
  final ValueNotifier<ReplayState> stateNotifier;

  ReplayController({required List<MoveRecord> history})
      : stateNotifier = ValueNotifier(ReplayState.initial(history));

  ReplayState get state => stateNotifier.value;

  // transport —— Task 5/6 实现
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/surround_game/replay_controller_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add lib/core/surround_game/replay/replay_controller.dart test/core/surround_game/replay_controller_test.dart
git commit -m "feat(surround_game): ReplayState + ReplaySpeed 值对象"
```

---

## Task 5: `ReplayController` 传输控件（步进/拖动/变速，不含自动播放）

**Files:**
- Modify: `lib/core/surround_game/replay/replay_controller.dart`（补全控制器方法）
- Test: `test/core/surround_game/replay_controller_test.dart`（追加 group）

- [ ] **Step 1: 写失败测试** —— 在 `replay_controller_test.dart` 的 `main()` 内追加：

```dart
  group('传输控件', () {
    test('stepForward / stepBackward clamp 不越界', () {
      final c = ReplayController(history: buildMixedGame().history);
      c.jumpToEnd();
      expect(c.state.cursor, c.state.totalMoves);
      c.stepForward();
      expect(c.state.cursor, c.state.totalMoves, reason: '到尾再前进不动');
      c.jumpToStart();
      expect(c.state.cursor, 0);
      c.stepBackward();
      expect(c.state.cursor, 0, reason: '到头再后退不动');
      c.dispose();
    });

    test('seek clamp 到 [0, length] 且暂停', () {
      final c = ReplayController(history: buildMixedGame().history);
      c.seek(99999);
      expect(c.state.cursor, c.state.totalMoves);
      expect(c.state.isPlaying, false);
      c.seek(-10);
      expect(c.state.cursor, 0);
      c.dispose();
    });

    test('stepForward 单步推进 + history 不被修改', () {
      final game = buildMixedGame();
      final c = ReplayController(history: game.history);
      final before = c.state.totalMoves;
      c.stepForward();
      expect(c.state.cursor, 1);
      expect(c.state.totalMoves, before, reason: 'history 只读');
      expect(() => c.state.history.add(game.history.first), throwsUnsupportedError,
          reason: 'history unmodifiable');
      c.dispose();
    });

    test('cycleSpeed 顺序 x1→x2→x4→x1', () {
      final c = ReplayController(history: buildMixedGame().history);
      expect(c.state.speed, ReplaySpeed.x1);
      c.cycleSpeed();
      expect(c.state.speed, ReplaySpeed.x2);
      c.cycleSpeed();
      expect(c.state.speed, ReplaySpeed.x4);
      c.cycleSpeed();
      expect(c.state.speed, ReplaySpeed.x1);
      c.dispose();
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/surround_game/replay_controller_test.dart`
Expected: FAIL —— `jumpToEnd`/`seek`/`stepForward`/`cycleSpeed` 等方法未实现。

- [ ] **Step 3: 实现传输方法** —— 把 `replay_controller.dart` 中 `// transport —— Task 5/6 实现` 这行替换为：

```dart
  Timer? _timer;

  void stepForward() {
    if (state.atEnd) {
      pause();
      return;
    }
    final next = state.cursor + 1;
    final reachedEnd = next >= state.totalMoves;
    _emit(cursor: next, playing: reachedEnd ? false : state.isPlaying);
    if (reachedEnd) _cancelTimer();
  }

  void stepBackward() {
    if (state.atStart) return;
    _emit(cursor: state.cursor - 1, playing: false);
    _cancelTimer();
  }

  void seek(int index) {
    final clamped = min(state.totalMoves, max(0, index));
    _emit(cursor: clamped, playing: false);
    _cancelTimer();
  }

  void jumpToStart() => seek(0);
  void jumpToEnd() => seek(state.totalMoves);

  void cycleSpeed() {
    final order = ReplaySpeed.values;
    final next = order[(order.indexOf(state.speed) + 1) % order.length];
    final wasPlaying = state.isPlaying;
    _emit(cursor: state.cursor, playing: wasPlaying, speed: next);
    if (wasPlaying) _startTimer(); // 按新间隔重建
  }

  // —— 内部 ——

  void _emit({required int cursor, bool? playing, ReplaySpeed? speed}) {
    final s = state;
    stateNotifier.value = ReplayState(
      history: s.history,
      cursor: cursor,
      speed: speed ?? s.speed,
      isPlaying: playing ?? s.isPlaying,
      board: QuoridorEngine.replayHistory(s.history, upTo: cursor),
    );
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _startTimer() {
    _cancelTimer();
    _timer = Timer.periodic(_intervalFor(state.speed), (_) => stepForward());
  }

  // play / pause / togglePlay —— Task 6 实现
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/surround_game/replay_controller_test.dart`
Expected: PASS（4 个传输用例 + initial）。

- [ ] **Step 5: Commit**

```bash
git add lib/core/surround_game/replay/replay_controller.dart test/core/surround_game/replay_controller_test.dart
git commit -m "feat(surround_game): ReplayController 传输控件 (步进/拖动/变速, 单测 4)"
```

---

## Task 6: `ReplayController` 自动播放（play/pause + 到尾自停，fake_async 测试）

**Files:**
- Modify: `lib/core/surround_game/replay/replay_controller.dart`（补 `play`/`pause`/`togglePlay`）
- Test: `test/core/surround_game/replay_controller_test.dart`（追加自动播放 group）

- [ ] **Step 1: 写失败测试** —— 在 `replay_controller_test.dart` 顶部加 import：

```dart
import 'package:fake_async/fake_async.dart';
```

在 `main()` 内追加：

```dart
  group('自动播放 (fake_async)', () {
    test('play → 逐手推进 → 到尾自停', () {
      fakeAsync((fa) {
        final game = buildMixedGame();
        final c = ReplayController(history: game.history);
        c.play();
        expect(c.state.isPlaying, true, reason: '播放中');
        fa.elapse(const Duration(seconds: 60)); // 远超总时长
        expect(c.state.cursor, game.history.length, reason: '应推到尾');
        expect(c.state.isPlaying, false, reason: '到尾自动暂停');
        c.dispose();
      });
    });

    test('togglePlay = play/pause 切换', () {
      fakeAsync((fa) {
        final c = ReplayController(history: buildMixedGame().history);
        c.togglePlay();
        expect(c.state.isPlaying, true);
        c.togglePlay();
        expect(c.state.isPlaying, false);
        c.dispose();
      });
    });

    test('变速后仍推进且更快（x2：800ms 内 2 步）', () {
      fakeAsync((fa) {
        final c = ReplayController(history: buildMixedGame().history);
        c.cycleSpeed(); // x1→x2（400ms/手）
        c.play();
        fa.elapse(const Duration(milliseconds: 800));
        expect(c.state.cursor, 2, reason: 'x2 下 800ms 应推进 2 步');
        c.dispose();
      });
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/surround_game/replay_controller_test.dart`
Expected: FAIL —— `play`/`pause`/`togglePlay` 未实现，`togglePlay` 用例会编译错或 play 不前进。

- [ ] **Step 3: 实现 play/pause/togglePlay + dispose** —— 把 `replay_controller.dart` 中 `// play / pause / togglePlay —— Task 6 实现` 替换为：

```dart
  void togglePlay() {
    if (state.isPlaying) {
      pause();
    } else {
      play();
    }
  }

  void play() {
    if (state.atEnd) return; // 到尾不播放
    _emit(cursor: state.cursor, playing: true);
    _startTimer();
  }

  void pause() {
    _cancelTimer();
    _emit(cursor: state.cursor, playing: false);
  }

  void dispose() {
    _cancelTimer();
    stateNotifier.dispose();
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/surround_game/replay_controller_test.dart`
Expected: PASS（自动播放 3 + 传输 4 + initial = 8）。

- [ ] **Step 5: Commit**

```bash
git add lib/core/surround_game/replay/replay_controller.dart test/core/surround_game/replay_controller_test.dart
git commit -m "feat(surround_game): ReplayController 自动播放 + 到尾自停 (fake_async 单测 3)"
```

---

## Task 7: `ReplayPage` 只读棋盘 + 传输条 + widget smoke

**Files:**
- Create: `lib/core/surround_game/pages/replay_page.dart`
- Test: `test/core/surround_game/replay_page_test.dart`

- [ ] **Step 1: 写 widget smoke 测试** —— 新建 `test/core/surround_game/replay_page_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/pages/replay_page.dart';
import '_fixtures.dart';

void main() {
  testWidgets('ReplayPage 渲染棋盘 + 传输条；步进更新步数', (tester) async {
    final game = buildMixedGame();
    await tester.pumpWidget(MaterialApp(home: ReplayPage(history: game.history)));
    await tester.pumpAndSettle();

    expect(find.text('回放'), findsOneWidget);
    expect(find.text('第 0 / ${game.history.length} 手'), findsOneWidget,
        reason: '初始步数文案');
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);

    // 点"下一步" → 步数 +1
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(find.text('第 1 / ${game.history.length} 手'), findsOneWidget);

    // 点"到尾" → 步数到终
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pump();
    expect(find.text('第 ${game.history.length} / ${game.history.length} 手'), findsOneWidget);
  });

  testWidgets('空棋谱不崩（Slider 隐藏，控件禁用）', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReplayPage(history: [])));
    await tester.pump();
    expect(find.text('第 0 / 0 手'), findsOneWidget);
    expect(find.byType(Slider), findsNothing, reason: 'totalMoves=0 时不渲染 Slider');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/surround_game/replay_page_test.dart`
Expected: FAIL —— `ReplayPage` 未定义。

- [ ] **Step 3: 实现 `ReplayPage`** —— 新建 `lib/core/surround_game/pages/replay_page.dart`：

```dart
// 只读回放页：复用 ChessBoard/ChessWall/ChessPlayer 渲染光标处棋盘 + 传输条。
// 无 TouchView / 无确认操作 / 无合法落子提示 —— 纯观察。
import 'package:flutter/material.dart';

import '../board_theme.dart';
import '../models/game_state.dart';
import '../replay/replay_controller.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_player.dart';
import '../widgets/chess_wall.dart';

class ReplayPage extends StatefulWidget {
  final List<MoveRecord> history;
  const ReplayPage({super.key, required this.history});

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage> {
  late final ReplayController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ReplayController(history: widget.history);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = BoardTheme.of(context);
    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: AppBar(
        title: const Text('回放'),
        backgroundColor: theme.panelBg,
        foregroundColor: theme.btnText,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final cellSize = w / 11;
                    return ValueListenableBuilder<ReplayState>(
                      valueListenable: _controller.stateNotifier,
                      builder: (_, rs, __) {
                        final gs = rs.board;
                        return SizedBox(
                          width: w,
                          height: w,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ChessBoard(cellSize: cellSize, theme: theme),
                              ChessWall(
                                history: gs.history,
                                cellSize: cellSize,
                                theme: theme,
                              ),
                              ChessPlayer(
                                cellId: gs.topPlayerId,
                                cellSize: cellSize,
                                color: theme.piecePlayerA,
                              ),
                              ChessPlayer(
                                cellId: gs.bottomPlayerId,
                                cellSize: cellSize,
                                color: theme.piecePlayerB,
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            ValueListenableBuilder<ReplayState>(
              valueListenable: _controller.stateNotifier,
              builder: (_, rs, __) => _TransportBar(
                state: rs,
                controller: _controller,
                theme: theme,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 传输条：步数/回合 + 按钮行 + scrub 滑块。
class _TransportBar extends StatelessWidget {
  final ReplayState state;
  final ReplayController controller;
  final BoardThemeData theme;

  const _TransportBar({
    required this.state,
    required this.controller,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.panelBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('第 ${state.cursor} / ${state.totalMoves} 手',
                  style: TextStyle(
                      color: theme.btnText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              Text(state.board.currentPlayerIsTop ? '上方回合' : '下方回合',
                  style: TextStyle(color: theme.btnSub, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _btn(Icons.skip_previous, '到头', controller.jumpToStart,
                  disabled: state.atStart),
              const SizedBox(width: 12),
              _btn(Icons.chevron_left, '上一步', controller.stepBackward,
                  disabled: state.atStart),
              const SizedBox(width: 12),
              _btn(
                state.isPlaying ? Icons.pause : Icons.play_arrow,
                state.isPlaying ? '暂停' : '播放',
                controller.togglePlay,
                disabled: state.atEnd,
                primary: true,
              ),
              const SizedBox(width: 12),
              _btn(Icons.chevron_right, '下一步', controller.stepForward,
                  disabled: state.atEnd),
              const SizedBox(width: 12),
              _btn(Icons.skip_next, '到尾', controller.jumpToEnd,
                  disabled: state.atEnd),
              const Spacer(),
              GestureDetector(
                onTap: controller.cycleSpeed,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.btnBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.btnBorder),
                  ),
                  child: Text(_speedLabel(state.speed),
                      style: TextStyle(
                          color: theme.btnText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (state.totalMoves > 0)
            Slider(
              min: 0,
              max: state.totalMoves.toDouble(),
              divisions: state.totalMoves,
              value: state.cursor.toDouble(),
              onChanged: (v) => controller.seek(v.round()),
              activeColor: theme.piecePlayerA,
              inactiveColor: theme.btnBorder,
            )
          else
            const SizedBox(height: 24),
        ],
      ),
    );
  }

  String _speedLabel(ReplaySpeed s) {
    switch (s) {
      case ReplaySpeed.x1:
        return '1x';
      case ReplaySpeed.x2:
        return '2x';
      case ReplaySpeed.x4:
        return '4x';
    }
  }

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool disabled = false, bool primary = false}) {
    final color = primary ? theme.piecePlayerA : theme.btnText;
    return Opacity(
      opacity: disabled ? 0.35 : 1.0,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/surround_game/replay_page_test.dart`
Expected: PASS（渲染 + 步进 + 空棋谱 2 用例）。

- [ ] **Step 5: Commit**

```bash
git add lib/core/surround_game/pages/replay_page.dart test/core/surround_game/replay_page_test.dart
git commit -m "feat(surround_game): ReplayPage 只读回放页 + 传输条 (widget smoke 2)"
```

---

## Task 8: 胜利弹层入口「观看回放」+ 导出 + 全量回归

**Files:**
- Modify: `lib/core/surround_game/pages/game_page.dart`（import + 胜利弹层按钮）
- Modify: `lib/core/surround_game/surround_game.dart`（导出）

- [ ] **Step 1: 加 import** —— 在 `game_page.dart` 顶部 import 区（`import '../widgets/player_panel.dart';` 之后）加：

```dart
import 'replay_page.dart';
```

- [ ] **Step 2: 改胜利弹层按钮** —— 在 `game_page.dart` 找到这段（胜利弹层 `再来一局` 按钮）：

```dart
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _controller.resetGame(),
                            style: FilledButton.styleFrom(
                              backgroundColor: winColor,
                            ),
                            child: const Text('再来一局'),
                          ),
```

替换为：

```dart
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ReplayPage(
                                        history:
                                            List.of(ui.gameState.history),
                                      ),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: winColor,
                                  side: BorderSide(color: winColor),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                ),
                                child: const Text('观看回放'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: () => _controller.resetGame(),
                                style: FilledButton.styleFrom(
                                  backgroundColor: winColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                ),
                                child: const Text('再来一局'),
                              ),
                            ],
                          ),
```

> `context` 取自外层 `_GamePageState.build` 的 BuildContext（胜利弹层的 `ValueListenableBuilder` 第一参命名为 `_`，未遮蔽外层 `context`）。`ui` 来自该 builder 的第二参，在作用域内。

- [ ] **Step 3: 导出新文件** —— 在 `surround_game.dart` 末尾追加：

```dart
export 'replay/replay_controller.dart';
export 'pages/replay_page.dart';
```

- [ ] **Step 4: 全量回归**

Run: `flutter analyze lib/core/surround_game test/core/surround_game`
Expected: No issues.

Run: `flutter test test/core/surround_game/`
Expected: 全绿（既有 + 新增：applyMoveRecord 3 + replay 5 + controller 8 + page 2）。

- [ ] **Step 5: 手测（emulator/设备）**

启动 app → 围追堵截 → 本地对战下到一方获胜 → 胜利弹层点「观看回放」→ 验证：
- 棋盘显示开局（两只棋子在起始位）；
- ▶ 播放逐手推进、⏸ 暂停、◀▶ 步进、⏮⏭ 到头到尾、滑块拖动、1x↔2x↔4x 切换；
- 到尾后播放自动停止；
- 返回后胜利弹层仍在，点「再来一局」可重开。

- [ ] **Step 6: Commit**

```bash
git add lib/core/surround_game/pages/game_page.dart lib/core/surround_game/surround_game.dart
git commit -m "feat(surround_game): 胜利弹层「观看回放」入口 + 导出"
```

---

## Self-Review（写完即自查，已在下文修正）

**1. Spec 覆盖** —— spec 各节对应任务：
- §4 引擎层（applyMoveRecord / replayHistory / 重构 / fromJson）→ Task 1/2/3 ✅
- §5 状态与控制器（ReplayState / ReplayController / autoplay）→ Task 4/5/6 ✅
- §6 回放页与入口（ReplayPage / 传输条 / 胜利弹层 / 导出）→ Task 7/8 ✅
- §7 测试（引擎 8 / 控制器 7+ / widget smoke）→ 散落在各 Task ✅
- §11 不在范围（持久化/LAN/平局弹层/墙计数条）→ 均未做 ✅

**2. 占位扫描** —— 无 TBD/TODO；每步含可执行代码或命令。

**3. 类型/命名一致性** —— `ReplayState`、`ReplayController`、`ReplaySpeed`、`applyMoveRecord`、`replayHistory`、`_recomputeTurn`、`buildMixedGame`、`_TransportBar` 跨任务一致 ✅。

**已修正（inline）：**
- Task 2 Step 2 的 `upTo clamp` 用例曾误含 `cursor0Top()` 占位行 —— 已删除，只保留两条有效断言。
- Task 2 Step 1 fixture 的 `for` 循环体已补 `if (state.validMoves.isEmpty) break;`，防 `Set.reduce` 空集边界。

---

## 收尾（可选）

- [ ] 在 `docs/围追堵截-Quoridor任务清单.md` 顶部追加"回放系统已完成"标记段（参考其 Phase 1 格式）。
