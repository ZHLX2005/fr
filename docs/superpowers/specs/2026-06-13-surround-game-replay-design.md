# 围追堵截 (Quoridor) 回放系统 — 设计文档

- **日期**：2026-06-13
- **范围**：`lib/core/surround_game/` — 引擎层新增重建原语 + 回放控制器/页面 + 胜利弹层入口
- **目标**：实现「可重放重建完整游戏状态」+「回放实战」—— 一局结束后可在棋盘上逐手回看，支持播放/暂停/步进/拖动/变速。
- **依赖前提**：Phase 1 引擎重写已完成（`QuoridorEngine` 纯函数 + 不可变 `GameState` + `history: List<MoveRecord>` 已序列化）。
- **预计工作量**：~3 小时（引擎原语 + 控制器 + 页面 + 入口 + 测试）

---

## 1. 决策快照

| 维度 | 决策 | 备注 |
|------|------|------|
| 交付范围 | 引擎重建原语 + 会话内回放查看器 | 不含持久化、不含 LAN 同步 UI |
| 回放来源 | 当前设备上「刚刚下完」的那局（`GamePage` 结束时的 `history`） | 会话内、内存态 |
| 传输控件 | 全量：⏮ ◀ ▶/⏸ ▶ ⏭ + 速度(1x/2x/4x) + 拖动滑块 | "回放实战"的完整体验 |
| 步退实现 | 从零重建（`replayHistory(history, upTo: cursor)`） | 不写逆操作；9×9 棋盘微秒级 |
| 回放状态来源 | `MoveRecord.isTopPlayer`（棋谱权威） | 不依赖 `currentPlayerIsTop` 预一致 |
| 放墙/走棋是否复验 | 否（信任棋谱） | 棋谱来自合法对局，是权威 |
| 层级 | 独立 `ReplayController` + 独立 `ReplayPage`（只读） | 不污染 `GameController`/`GamePage` 的交互逻辑 |

---

## 2. 与现状的衔接

- `GameState` 已持有 `history: List<MoveRecord>` 并已 `toJson`/`fromJson` 序列化 —— 回放的数据源已就绪。
- `game_state.dart:196-200` 明确记载：反序列化后 `adjacency`/`wallGrid` 不可靠，需 `QuoridorEngine.replayHistory(history)` 重建，"下轮 LAN 同步时解决"。本设计顺带补上这个方法并修复 `fromJson`。
- `QuoridorEngine` 为全静态纯函数 `(state, args) -> newState`；新增方法延续此风格。
- `GamePage` 胜利弹层已有「再来一局」按钮，「观看回放」入口自然落在此处。
- 本 app 持久化用 Hive（`body_record_repo`、`hive_timetable_repository`），但**本设计不引入持久化**。

---

## 3. 文件清单

```
lib/core/surround_game/
├── engine/game_engine.dart            # ✏️ 新增 applyMoveRecord / replayHistory；重构 switchTurn；新增 _recomputeTurn
├── models/game_state.dart             # ✏️ fromJson 注释更新：调用方需 replayHistory 重建（保持 model 不依赖 engine，见 §10）
├── replay/replay_controller.dart      # 🆕 ReplayState + ReplaySpeed + ReplayController
├── pages/replay_page.dart             # 🆕 只读回放页（复用 ChessBoard/ChessWall/ChessPlayer）+ 传输条
├── pages/game_page.dart               # ✏️ 胜利弹层增加「观看回放」按钮 → push ReplayPage
└── surround_game.dart                 # ✏️ 导出 replay_controller / replay_page

test/core/surround_game/
├── game_engine_test.dart              # ✏️ 新增 group('replay') ~8 用例
├── replay_controller_test.dart        # 🆕 ~7 用例（含 fake_async 自动播放）
├── replay_page_test.dart              # 🆕 1 个 widget smoke（可选）
└── _fixtures.dart                     # 🆕（按需）确定性混合对局 fixture
```

---

## 4. 引擎层（Section 1）

### 4.1 `applyMoveRecord(GameState state, MoveRecord record) -> GameState`

信任棋谱、只做几何重建、不复验合法性。两个分支：

- **走棋**（`record.isWall == false`）：`cellId = record.x + record.y * 9`；按 **`record.isTopPlayer`**（非 `state.currentPlayerIsTop`）更新 `topPlayerId`/`bottomPlayerId`；追加 `history`。
- **放墙**（`record.isWall == true`）：`wallOccupiedCells` 标记 `wallGrid`；`applyWallToAdjacency(..., isPlacing: true)` 切断邻接；该方墙计数 +1；追加 `history`。

不改 `currentPlayerIsTop`、不算 `validMoves`（与现有 `movePiece`/`placeWall` 的"动作 vs 换手分离"约定一致）。

### 4.2 `replayHistory(List<MoveRecord> history, {int? upTo}) -> GameState`

```dart
static GameState replayHistory(List<MoveRecord> history, {int? upTo}) {
  final n = upTo?.clamp(0, history.length) ?? history.length;
  var state = initialize();
  for (var i = 0; i < n; i++) {
    state = applyMoveRecord(state, history[i]);
  }
  final isTop = (n == 0) ? true : !history[n - 1].isTopPlayer;
  return _recomputeTurn(state, isTop);
}
```

- `upTo` = 光标（已应用的步数，0=开局，length=终局），`clamp` 保证任意 seek 安全。
- 步退即"从零重建到光标"：cursor 10 → 5 只需 `replayHistory(history, upTo: 5)`。无逆操作、无累积漂移；≤~40 手微秒级。

### 4.3 行为保持重构 + `fromJson` 修复

- 抽取 `_recomputeTurn(state, isTop)`：现有 `switchTurn` 的函数体正是"翻手 + 重算 validMoves/status"。`switchTurn` 改为一行委托。**行为完全不变**，仅消除重复，供 `replayHistory` 复用。
- `GameState.fromJson` **保持只返回原始对象**（`adjacency`/`wallGrid` 留空），以维持 `game_state.dart` 既有的"model 不反向依赖 engine"约束（详见 §10 依赖方向）。反序列化方负责显式调用 `QuoridorEngine.replayHistory(state.history)` 重建。这**关闭 `game_state.dart:196-200` 的已知局限**：原局限是"没有重建手段"，现在手段存在且文档化；后续 LAN 同步/回放共用同一原语。

### 4.4 设计要点

- **信任 + 仅几何**：重放合法棋谱无需重跑 BFS 路径校验或跳跃规则，只重画墙、重摆子。健壮且快。
- **回合真相单一来源**（`record.isTopPlayer`）：重建不依赖回合态预先一致。
- **一个原语三用**：回放光标、`fromJson` 正确性、（后续）LAN 同步 —— 全走 `replayHistory`。

**核心不变量（必须测）**：任意经活路径下出的对局，`replayHistory(finalHistory, upTo: k)` 必须与第 k 手后的活状态完全一致。此不变量成立 ⇒ 回放不会"撒谎"。

---

## 5. 回放状态与控制器（Section 2）

新文件 `lib/core/surround_game/replay/replay_controller.dart`，仿现有 `GameController`/`GameUiState` 形态。

### 5.1 `ReplayState`（不可变值对象）

```dart
enum ReplaySpeed { x1, x2, x4 }   // 倍率；间隔 = baseMs / mult

class ReplayState {
  final List<MoveRecord> history;   // 完整棋谱（固定，unmodifiable）
  final int cursor;                 // 0..history.length
  final ReplaySpeed speed;
  final bool isPlaying;             // 是否自动推进
  final GameState board;            // 缓存：replayHistory(history, upTo: cursor)

  int  get totalMoves => history.length;
  bool get atStart    => cursor == 0;
  bool get atEnd      => cursor >= history.length;

  ReplayState copyWith({...});
  factory ReplayState.initial(List<MoveRecord> history) => ReplayState(
    history: List.unmodifiable(history),
    cursor: 0, speed: ReplaySpeed.x1, isPlaying: false,
    board: QuoridorEngine.replayHistory(history, upTo: 0),
  );
}
```

- `board` 在控制器**发射新状态时计算一次**（非每次 build 才算的 getter），使 `ValueNotifier` 载荷自洽、widget build 为纯读。
- `history` 存为 `unmodifiable`，回放器绝不修改源棋谱。

### 5.2 `ReplayController`（驱动 `ValueNotifier<ReplayState>`）

```dart
class ReplayController {
  final ValueNotifier<ReplayState> stateNotifier;
  Timer? _timer;

  ReplayController({required List<MoveRecord> history})
    : stateNotifier = ValueNotifier(ReplayState.initial(history));

  void togglePlay();     // play / pause
  void stepForward();    // cursor = min(cursor+1, length)；到尾自动暂停
  void stepBackward();   // cursor = max(cursor-1, 0)
  void seek(int index);  // clamp [0, length]
  void jumpToStart();    // seek(0) + 暂停
  void jumpToEnd();      // seek(length) + 暂停
  void cycleSpeed();     // x1→x2→x4→x1；播放中重建 timer
  void dispose();        // _timer?.cancel(); stateNotifier.dispose()
}
```

内部：
- **`_emit(int cursor, {bool? playing, ReplaySpeed? speed})`** 私有助手：构造下一个 `ReplayState`（用 `replayHistory(history, upTo: cursor)` 重算 `board`）赋给 `stateNotifier`。所有导航都走它，`board` 永远与 `cursor` 同步。
- **自动播放**用普通 `Timer.periodic`（非 `Ticker` —— `Ticker` 需 widget 树的 `TickerProvider`，`Timer` 解耦更简）。间隔 = `_intervalFor(speed)`（如 `800ms / mult`）。每 tick → `stepForward()`；若 `atEnd` 则暂停（取消 timer）。
- **播放中变速**取消并以新间隔重建 timer；**暂停/seek/jump**取消 timer 并置 `isPlaying=false`；**`stepForward` 到尾**自动暂停。

### 5.3 参数选择（已定）

- **基准间隔 800ms @ 1x**（→ 400ms @2x、200ms @4x）。文件顶部可调常量。
- 手动与自动推进共用 `stepForward` 的 clamp/pause 逻辑（单一处拥有到尾暂停）。
- 不耦合 `TickerProvider` —— `ReplayController` 是 page 持有并 dispose 的普通对象，与 `GameController` 一致。

---

## 6. 回放页与入口（Section 3）

### 6.1 新文件 `lib/core/surround_game/pages/replay_page.dart`

只读棋盘（复用现有 widget）+ 传输条。**无** `TouchView`、**无** `ConfirmActions`、**无** 合法落子提示 —— 纯观察。

布局：
```
┌─────────────────────────────────┐
│  ←  回放            第 12 / 30 手│  AppBar（标题 + 步数）
├─────────────────────────────────┤
│        9×9 棋盘（只读）          │  ChessBoard + ChessWall + 2× ChessPlayer
│        （光标处的棋子与墙）       │  数据源 state.board
├─────────────────────────────────┤
│   ⏮   ◀   ▶/⏸   ▶   ⏭    [1x]  │  传输行
│   ├──●─────────────────|        │  Slider(0..totalMoves, value=cursor) → seek
│   上方回合                       │  光标处回合指示
└─────────────────────────────────┘
```

**棋盘栈**（沿用 `GamePage` 的 `LayoutBuilder`，`cellSize = w/11`、`distance = cellSize*1.25`）：
- `ChessBoard(cellSize, theme)`
- `ChessWall(history: state.board.history, cellSize, theme)` —— 因 `replayHistory` 把 `board.history` 重建为已应用前缀，自然只渲染到光标为止的墙。
- `ChessPlayer(cellId: state.board.topPlayerId, …)` / `ChessPlayer(cellId: state.board.bottomPlayerId, …)`

**传输条** `Column` 两行：
1. 按钮行：`jumpToStart` ⏮ · `stepBackward` ◀ · `togglePlay` ▶/⏸ · `stepForward` ▶ · `jumpToEnd` ⏭ · `cycleSpeed`（文案 `1x`/`2x`/`4x`）。`atStart` 时禁用 ◀/⏮；`atEnd` 时禁用 ▶/⏭/播放。
2. `Slider(min:0, max: totalMoves, value: cursor)` → `onChanged: controller.seek`，拖动即 scrub（每点重建）。

**回合指示 + 步数**（"第 C / N 手"）用 `state.board.currentPlayerIsTop` 与 `state.cursor`/`totalMoves`。

**PlayerPanel**：现有 `PlayerPanel` 交互式（点击切模式），回放中不宜复用。采用轻量只读墙计数条（`wallCountPerPlayer − board.topWallsPlaced/bottomWallsPlaced`）为**可选打磨**；棋盘 + 传输条是核心交付。

**生命周期**：`ReplayPage` 为 `StatefulWidget`；`initState` 建 `ReplayController(history: widget.history)`，`dispose` 调 `controller.dispose()`。页面参数 `final List<MoveRecord> history`。

### 6.2 入口 —— 改 `game_page.dart` 胜利弹层

胜利弹层现有单个 `FilledButton('再来一局')`，改为 `Row` 两按钮：

```dart
Row(children: [
  OutlinedButton(onPressed: () => Navigator.push(context,
      MaterialPageRoute(builder: (_) => ReplayPage(history: ui.gameState.history))),
    child: const Text('观看回放')),          // 新增
  FilledButton(onPressed: _controller.resetGame, child: const Text('再来一局')),  // 既有
])
```

点击时从 `ui.gameState.history` 取棋谱；弹层仅在终局显示，棋谱完整。（平局当前无弹层 —— 平局回放入口为小后续，本轮不纳入。）

### 6.3 导出 —— 改 `surround_game.dart`

```dart
export 'replay/replay_controller.dart';
export 'pages/replay_page.dart';
```

---

## 7. 测试计划（Section 4）

沿用仓库约定（`test/core/surround_game/`、`flutter_test`、中文 test 名、每条 `expect` 配 `reason:`、按方法 `group`）。

### 7.1 引擎层 —— 扩展 `game_engine_test.dart`（新 `group('replay')` ~8 用例）

| # | 用例 | 期望 |
|---|------|------|
| 1 | `applyMoveRecord` 走棋 | 移动方 cellId 更新；`history` +1 |
| 2 | `applyMoveRecord` 放墙 | `wallGrid` 3 格 true；邻接切断；该方墙计数 +1 |
| 3 | `applyMoveRecord` 不看 `currentPlayerIsTop` | 按 `record.isTopPlayer` 应用 |
| 4 | `replayHistory([])` | 等于 `initialize()` |
| 5 | `replayHistory(h, upTo: k)` clamp | `upTo<0`→0、`>length`→length |
| 6 | **replay ≡ live（核心不变量）** | 下出一局混合对局（走+墙+跳），每手后快照 `adjacency`/`wallGrid`/位置；断言 `replayHistory(finalHistory, upTo: k)` 复现每个快照，∀k |
| 7 | 回放后回合 | `currentPlayerIsTop = !history[k-1].isTopPlayer`（k=0 时 true）；`status`/`validMoves` 与 `switchTurn` 一致 |
| 8 | `fromJson` + 调用方 `replayHistory` 闭环 | `GameState.fromJson(s.toJson())` 后由调用方 `replayHistory(state.history)` → `adjacency`/`wallGrid`/`validMoves` 与 `s` 一致（关闭已知局限） |

用例 6 为承重测试 —— 通过即证明回放绝不与真实对局脱节。确定性混合对局抽到 `test/core/surround_game/_fixtures.dart`（若复用）。

### 7.2 控制器 —— 新 `replay_controller_test.dart`（~7 用例）

| # | 用例 | 期望 |
|---|------|------|
| 1 | 初始 | `cursor==0`、`!isPlaying`、`board==initialize()` |
| 2 | `stepForward`/`stepBackward` clamp | 不越 `[0, length]` |
| 3 | `seek` clamp | 越界索引钉到边界 |
| 4 | `jumpToStart`/`jumpToEnd` | cursor→0/length 且 `isPlaying=false` |
| 5 | `cycleSpeed` | x1→x2→x4→x1 |
| 6 | 自动播放推进 + 到尾自停 | `FakeAsync` 下推进时间使 cursor 前进；`atEnd` 时 `isPlaying` 翻 false 且 timer 取消 |
| 7 | 播放中变速 | timer 按新间隔重建（cursor 仍前进、更快） |

**自动播放确定性**：`Timer.periodic` 难对墙钟断言。用例 6/7 用 `package:fake_async`（`flutter_test` 传递依赖，无新 app 依赖）驱动时钟。若不愿引入 `fake_async`，回退方案为可注入 timer 工厂 —— 但 `fake_async` 更轻，推荐。

### 7.3 Widget smoke（可选，精简）

新 `replay_page_test.dart` 单个 `testWidgets`：挂载短 fixture 的 `ReplayPage`，断言棋盘渲染、点 ▶ 再 ⏭ 落到终局（不崩、传输按钮在边界处启用/禁用正确）。引擎 + 控制器测试已承载正确性，此 smoke 只守住接线。

---

## 8. 错误处理（汇总）

- 空/零长棋谱 → 开局棋盘，所有控件 at-start；不崩。
- `seek`/越界 → clamp。
- 自动播放到尾 → 自停 + 取消 timer。
- 畸形棋谱（后续经 `fromJson`/LAN）→ 尽力几何重建、不崩（已越界保护）；复验**不是**回放的职责。

---

## 9. 执行计划（参考，每阶段一 atomic commit + `flutter analyze` 0 error + 对应单测绿）

```
┌──────────────────────────────────────────────────┐
│ R0  引擎 applyMoveRecord + replayHistory +        │
│     switchTurn 重构 + fromJson 修复  ~50min │commit│
│ R1  replay_controller + 单测          ~50min │commit│
│ R2  replay_page + 胜利弹层入口 + 导出   ~50min │commit│
│ R3  widget smoke + 文档收尾            ~20min │commit│
└──────────────────────────────────────────────────┘
```

- **R0**：engine 改动 + `group('replay')` 8 用例；`fromJson` 往返用例（用例 8）证明局限已修复。
- **R1**：`ReplayController` + 7 用例（fake_async 自动播放）。
- **R2**：`ReplayPage` 只读棋盘 + 传输条 + 胜利弹层「观看回放」+ 导出；手测进入回放、步进、播放、变速、scrub。
- **R3**：widget smoke；`docs/围追堵截-Quoridor任务清单.md` 追加本轮完成标记。

---

## 10. 风险与回退

| 风险 | 应对 |
|------|------|
| `replay ≡ live` 不变量在跳跃/平局边角失败 | 用例 6 直接断言每手快照；先修不变量再继续 |
| `switchTurn` 重构引入行为漂移 | 行为保持；既有 26 引擎用例兜底，且重构后 `switchTurn` 委托同一函数体 |
| `Timer.periodic` 自动播放测试 flaky | 用 `fake_async` 驱动时钟，不依赖墙钟 |
| `fromJson` 调 `replayHistory` 引入循环依赖（model→engine） | `game_state.dart` 已 import engine 路径需评估；若成环，改为 `fromJson` 仅返回原始对象、由调用方显式 `replayHistory`（保持 model 不依赖 engine 的既有约束） |
| 胜利弹层历史被 reset 清空 | 按钮仅在终局可见；点击时即时取 `ui.gameState.history` |

> **依赖方向待定（R0 内确认）**：`game_state.dart` 注释明确"model 不反向依赖 engine"。若 `fromJson` 内部调 `replayHistory` 会打破该约束。两个选项：
> - **选项 A（推荐）**：`fromJson` 保持只返回原始对象（`adjacency`/`wallGrid` 留空），由**调用方**在反序列化后显式 `QuoridorEngine.replayHistory(state.history)`。不破坏层级，文档更新即可。
> - **选项 B**：放宽约束，`fromJson` 内部调用 `replayHistory`。更省心但 model→engine 依赖。
>
> 默认按 **选项 A** 落地，更新 `game_state.dart:196-200` 注释为"调用方需 `replayHistory` 重建（见 SurroundGameService / ReplayController）"。

---

## 11. 不在本轮范围

显式排除（避免范围漂移）：

- ❌ 持久化 / Hive 对局存档（会话内内存态）
- ❌ LAN 中途重连同步 UI（引擎原语已就位，供后续轮使用）
- ❌ 平局弹层的回放入口（小后续）
- ❌ 只读墙计数条 / 分析提示（打磨，可同 PR 或后置）
- ❌ 官方斜跳、悔棋（沿用 Phase 1 决策，不在范围）

---

## 12. 参考索引

| 位置 | 关键 | 说明 |
|------|------|------|
| `game_state.dart:131` | `history: List<MoveRecord>` | 回放数据源（已序列化） |
| `game_state.dart:196-200` | `fromJson` 注释 | 已知局限（本轮用 replayHistory 解决） |
| `game_engine.dart:291` | `switchTurn` | 重构为委托 `_recomputeTurn` |
| `game_engine.dart:223`/`:364` | `movePiece`/`placeWall` | 动作 vs 换手分离的范式参照 |
| `game_ui_state.dart:91` | `GameController` | `ReplayController` 的形态参照 |
| `game_page.dart:217` | 胜利弹层 | 「观看回放」入口落点 |
| `widgets/chess_wall.dart` | `ChessWall(history:…)` | 复用，渲染光标前缀墙 |
