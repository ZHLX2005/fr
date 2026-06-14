# 围追堵截 (Quoridor) 悔棋功能 — 设计文档

- **日期**：2026-06-13
- **范围**：`lib/core/surround_game/` — `GameController` 新增 `undoLastMove` + `GamePage` 悔棋按钮 + 请求/同意/拒绝弹层
- **目标**：本地双人对局中，一方请求悔棋，另一方同意/拒绝；同意则撤销最后一步（走棋或放墙），回合回到该步执行者。
- **依赖前提**：回放系统的 `QuoridorEngine.replayHistory(history, {upTo})` 已就绪（悔棋 = 从历史前缀重建状态）。
- **预计工作量**：~1.5 小时（控制器方法 + 弹层 UI + 测试）

---

## 1. 决策快照

| 维度 | 决策 | 备注 |
|------|------|------|
| 适用范围 | 仅本地双人（单设备轮流） | LAN 对局尚未联网，LAN 悔棋延后 |
| 撤销粒度 | 每次撤销最后 1 步（半回合） | 重复点可连续悔；"弹出历史栈顶" |
| 状态回退机制 | `replayHistory(history, upTo: length-1)` | 复用回放原语，无需逆操作；正确性已被 `replay ≡ live` 不变量证明 |
| 请求/同意/拒绝 | 纯 UI 弹层（`GamePage` 内） | 弹层即"对方裁决"；不做身份校验（同屏双人） |
| 可用时机 | 对局进行中（status=running）且历史非空 | 终局弹层不提供悔棋（用"再来一局"） |
| 引擎层改动 | 无 | 只用已有 `replayHistory` |

---

## 2. 与现状的衔接

- `GameState.history: List<MoveRecord>` 当前为只追加；悔棋不在引擎层"删除"，而是由控制器用 `replayHistory(前缀)` 重建一个更短的 history 的新 state（语义等价于弹出栈顶）。
- `QuoridorEngine.replayHistory(history, {upTo})`（回放系统产物）从 `initialize()` + 历史前缀重建完整状态，含 `currentPlayerIsTop`/`validMoves`/`status`。`upTo: length-1` 即"撤销最后一步"。
- 回合正确性：`replayHistory` 的回合派生自最后一条记录 —— 撤销玩家 P 的那步后，`currentPlayerIsTop` 回到 P（其可重下）。即标准"悔棋/takeback"语义。
- `GamePage` 已有底部"重新开始"按钮 + `_showResetConfirm` 底部弹层样式，悔棋按钮与弹层沿用同款。
- 已知无关缺陷：`test/core/surround_game/game_ui_state_test.dart` 引用已删除的 `wallColor` getter，编译失败。**本功能不修它**（范围外），悔棋测试放到新文件 `undo_test.dart` 以绕开。建议另行清理。

---

## 3. 文件清单

```
lib/core/surround_game/
├── game_ui_state.dart   # ✏️ GameController 新增 undoLastMove()
└── pages/game_page.dart # ✏️ 底部"悔棋"按钮 + _showUndoRequestConfirm 弹层

test/core/surround_game/
└── undo_test.dart       # 🆕 控制器悔棋正确性 + 悔棋按钮/弹层 widget smoke
```

---

## 4. 控制器层（Section 1）

`GameController.undoLastMove() -> bool`（`game_ui_state.dart`）：

```dart
/// 悔棋：撤销最后一步（走棋或放墙），回合回到该步的执行者。
///
/// 实现 = 用 replayHistory(history, upTo: length-1) 从历史前缀重建完整状态。
/// 重建会一次性恢复：棋子位置、墙壁占用、墙计数、当前回合、validMoves、status。
/// 因此"悔棋"= 弹出历史栈顶 + 重放，无需任何逆操作。
///
/// - 空历史（开局）→ 无操作，返回 false。
/// - 终局后也可悔棋：撤回制胜的那步，status 回到 running（但 UI 仅在 running 时暴露按钮）。
/// - 同时清空任何待确认的走棋/放墙（重建一个干净 idle 的 GameUiState）。
bool undoLastMove() {
  final gs = state.gameState;
  if (gs.history.isEmpty) return false;
  final undone = QuoridorEngine.replayHistory(
    gs.history, upTo: gs.history.length - 1,
  );
  stateNotifier.value = GameUiState(gameState: undone);
  return true;
}
```

设计要点：
- **复用已证原语**：`replayHistory(upTo: length-1)` 正是 `replay ≡ live` 不变量覆盖的前缀之一 —— 悔棋正确性已被证明（悔后态 = 最后一步之前的状态）。
- **回合正确**：撤销玩家 P 的那步后 `currentPlayerIsTop` 回到 P（可重下）。
- **无引擎改动**、无逆操作、无逆操作配对。
- **干净重置**：`GameUiState(gameState: undone)` 重置 `mode`/`phase`/`pending`（与 `confirmAction`/`cancelAction` 一致）。
- 返回 `bool`，UI 据此知道是否真的悔了（空历史 → 无操作）。

---

## 5. 请求弹层与按钮（Section 2）

### 5.1 悔棋按钮（`GamePage` 底部）

现有底部"重新开始"在 `Align(centerLeft)` 内一个 `Row[refresh + 重新开始]`。改为同一 `Row` 里再加一个悔棋项：`Row[ undo + 悔棋 | gap | refresh + 重新开始 ]`。

- 文案 `悔棋`，图标 `Icons.undo`，颜色用 `theme.btnText.withValues(alpha: 0.5)`（与"重新开始"一致）。
- 启用条件：`status == GameStatus.running && gs.history.isNotEmpty`。否则 `onTap: null` + 更低透明度（禁用态）。

### 5.2 请求弹层 `_showUndoRequestConfirm(context, theme)`

仿 `_showResetConfirm` 的 `showModalBottomSheet`：

```
┌───────────────────────────┐
│  ━━ (拖拽条)               │
│  ↩ (undo icon)            │
│  对方请求悔棋               │
│  将撤销上一步，回合回到       │
│  上一步的执行者              │
│  [ 拒绝 ]    [ 同意 ]       │
└───────────────────────────┘
```

- **拒绝** → `Navigator.pop(ctx)`（什么都不做）。
- **同意** → `Navigator.pop(ctx); _controller.undoLastMove();`。
- 样式令牌、圆角、按钮排布与 `_showResetConfirm` 一致（拒绝 = `OutlinedButton`，同意 = `FilledButton`，主色 `theme.piecePlayerA`）。

### 5.3 流程与边界

- 点击悔棋 → `_showUndoRequestConfirm` → 弹层 → 同意 → `undoLastMove()`。
- 同意后若处于终局之外（running），棋盘自动刷新到悔后态；`undoLastMove` 重建的 `GameUiState` 为 idle，无残留拖拽/确认。
- 终局弹层（胜利）不提供悔棋入口（对局已结束）。
- 不做"谁可请求"的身份校验：同屏双人，谁点谁即请求方，弹层面向"对方"裁决。

---

## 6. 测试计划（Section 3）

新文件 `test/core/surround_game/undo_test.dart`（绕开 `game_ui_state_test.dart` 的预存编译失败）。

### 6.1 控制器（~4 用例）

| # | 用例 | 期望 |
|---|------|------|
| 1 | 走若干步后 `undoLastMove` | history 长度 -1；`currentPlayerIsTop` = 被撤销那步的执行者；返回 true |
| 2 | 含放墙的局面悔棋 | 该步墙计数 -1、wallGrid/邻接恢复到放墙前；与"放墙前的活状态"一致 |
| 3 | 空历史悔棋 | 无操作、返回 false、状态不变 |
| 4 | 悔棋 == 最后一步之前的状态 | 用活路径下出 N 步并快照，`undoLastMove` 后的 state == 第 N-1 步后的快照（复用 `_fixtures` 思路或直接活路径） |

> 用例 4 与回放系统的 `replay ≡ live` 不变量同源，此处给悔棋一个聚焦断言。

### 6.2 Widget smoke（~2 用例）

| # | 用例 | 期望 |
|---|------|------|
| 5 | 开局悔棋按钮禁用；下一步后可点 | 开局 `悔棋` 禁用；走一步后可点 |
| 6 | 悔棋流程：点悔棋 → 同意 → 棋子回到上一位置；拒绝 → 不变 | 走一步后点悔棋 → 弹层 → 同意 → topPlayerId 回到起点；拒绝 → 维持 |

> Widget 用 `MaterialApp(home: GamePage())`，通过 `ChessPlayer` 的 cellId 或步数文案断言悔棋生效。

---

## 7. 错误处理

- 空历史悔棋 → 控制器无操作返回 false；按钮禁用。
- 终局悔棋 → 引擎/控制器支持，但 UI 仅 running 时暴露按钮（不引入终局入口）。
- 悔棋时若有 pending 确认 → 重建干净 `GameUiState`，自然清除。

---

## 8. 执行计划（参考，每阶段一 atomic commit + `flutter analyze` 0 error + 对应单测绿）

```
┌──────────────────────────────────────────────────┐
│ U0  GameController.undoLastMove + 控制器单测 ~30min │commit│
│ U1  GamePage 悔棋按钮 + 请求弹层 + widget smoke ~40min │commit│
│ U2  全量回归（analyze + 相关测试）+ 验收 ~10min │commit│
└──────────────────────────────────────────────────┘
```

---

## 9. 风险与回退

| 风险 | 应对 |
|------|------|
| 悔棋回合方向错（回到错误一方） | 用例 1/4 直接断言 `currentPlayerIsTop`；且已被 `replay ≡ live` 覆盖 |
| 弹层样式与既有不一致 | 沿用 `_showResetConfirm` 结构与令牌 |
| `game_ui_state_test.dart` 预存失败干扰 | 悔棋测试放新文件 `undo_test.dart`；回归只跑相关文件 |
| 终局后误入悔棋 | UI 仅 running 暴露按钮；引擎支持但不暴露 |

---

## 10. 不在本轮范围

- ❌ LAN 联网悔棋（LAN 对局尚未联网）
- ❌ 悔棋次数限制 / 悔棋计数显示
- ❌ 多步批量悔棋（每次 1 步，重复点）
- ❌ 终局弹层的悔棋入口
- ❌ 修复 `game_ui_state_test.dart` 的 `wallColor` 预存失败（另行清理）

---

## 11. 参考索引

| 位置 | 关键 | 说明 |
|------|------|------|
| `engine/game_engine.dart` | `replayHistory(history, {upTo})` | 悔棋的回退原语（回放系统产物） |
| `game_ui_state.dart` | `GameController` | `undoLastMove` 落点；`GameUiState(gameState:)` 干净重置范式 |
| `pages/game_page.dart` | 底部"重新开始" + `_showResetConfirm` | 悔棋按钮与弹层的样式参照 |
| `test/core/surround_game/_fixtures.dart` | `buildMixedGame` | 悔棋正确性测试可复用 |
