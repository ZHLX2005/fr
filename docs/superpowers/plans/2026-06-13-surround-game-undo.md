# 围追堵截 (Quoridor) 悔棋功能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本地双人对局中，一方点"悔棋"→ 弹层请求 → 对方同意则撤销最后一步（回合回到该步执行者），拒绝则不动。

**Architecture:** 控制器新增 `undoLastMove()`，用回放系统的 `QuoridorEngine.replayHistory(history, upTo: length-1)` 重建状态（无需引擎改动、无需逆操作）。`GamePage` 加"悔棋"按钮（仅 running+历史非空时启用）+ 仿"重新开始"的请求弹层。

**Tech Stack:** Dart / Flutter，`flutter_test`。

**关联 spec：** `docs/superpowers/specs/2026-06-13-surround-game-undo-design.md`

---

## 文件结构

| 文件 | 操作 | 职责 |
|------|------|------|
| `lib/core/surround_game/game_ui_state.dart` | 修改 | `GameController` 新增 `undoLastMove() -> bool` |
| `lib/core/surround_game/pages/game_page.dart` | 修改 | 底部"悔棋"按钮（包 ValueListenableBuilder）+ `_showUndoRequestConfirm` 弹层 + `_bottomAction` 辅助 |
| `test/core/surround_game/undo_test.dart` | 新建 | 控制器悔棋正确性（~4）+ widget 存在性 smoke（1） |

测试命令：`flutter test test/core/surround_game/undo_test.dart`；分析：`flutter analyze lib/core/surround_game`。

> 注意：`test/core/surround_game/game_ui_state_test.dart` 有**预存无关编译失败**（`wallColor`），不在本功能范围。回归只跑相关文件，不跑该文件。

---

## Task 1: `GameController.undoLastMove()` + 控制器单测

**Files:**
- Modify: `lib/core/surround_game/game_ui_state.dart`（`GameController` 内，`cancelAction` 附近新增方法）
- Test: `test/core/surround_game/undo_test.dart`（新建）

- [ ] **Step 1: 写失败测试** —— 新建 `test/core/surround_game/undo_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/game_ui_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';

void main() {
  group('GameController.undoLastMove', () {
    test('空历史 → 无操作、返回 false', () {
      final c = GameController();
      expect(c.state.gameState.history.isEmpty, true);
      expect(c.undoLastMove(), false);
      expect(c.state.gameState.history.isEmpty, true);
    });

    test('走一步后悔棋 → history -1、回合回到 top、棋子回起点', () {
      // 用引擎构造"top 走到 cellId 13 后换手"的状态，注入控制器
      var gs = QuoridorEngine.initialize();
      gs = QuoridorEngine.switchTurn(QuoridorEngine.movePiece(gs, 13)!);
      final c = GameController()..stateNotifier.value = GameUiState(gameState: gs);

      expect(c.state.gameState.history.length, 1);
      expect(c.state.gameState.currentPlayerIsTop, false, reason: '换手到 bottom');

      expect(c.undoLastMove(), true);
      expect(c.state.gameState.history.length, 0, reason: 'history 弹栈');
      expect(c.state.gameState.currentPlayerIsTop, true, reason: '回合回到 top');
      expect(c.state.gameState.topPlayerId, SurroundGameConstants.topPlayerStart,
          reason: '棋子回到起点');
    });

    test('放墙后悔棋 → 墙计数/墙位恢复', () {
      var gs = QuoridorEngine.initialize();
      gs = QuoridorEngine.switchTurn(
          QuoridorEngine.placeWall(gs, 3, 4, WallOrientation.horizontal)!);
      final c = GameController()..stateNotifier.value = GameUiState(gameState: gs);

      expect(c.state.gameState.topWallsPlaced, 1);
      expect(c.state.gameState.wallGrid[160], true, reason: '放墙后中心格被占');

      expect(c.undoLastMove(), true);
      expect(c.state.gameState.topWallsPlaced, 0, reason: '墙计数恢复');
      expect(c.state.gameState.wallGrid[160], false, reason: '墙位恢复');
      expect(c.state.gameState.history.length, 0);
    });

    test('悔棋 == 最后一步之前的状态（多步混合）', () {
      // 活路径下 3 步，快照"第 2 步后"的状态（= 撤销第 3 步后的预期态）
      var gs = QuoridorEngine.initialize();
      gs = QuoridorEngine.switchTurn(QuoridorEngine.movePiece(gs, 13)!); // 第1步 top 走
      gs = QuoridorEngine.switchTurn(QuoridorEngine.movePiece(gs, 67)!); // 第2步 bottom 走
      final beforeLast = gs; // 快照：第2步后
      gs = QuoridorEngine.switchTurn(
          QuoridorEngine.placeWall(gs, 3, 4, WallOrientation.horizontal)!); // 第3步 top 放墙

      final c = GameController()..stateNotifier.value = GameUiState(gameState: gs);
      expect(c.undoLastMove(), true);

      final undone = c.state.gameState;
      // 悔后态应 == beforeLast（撤销了最后那步放墙）
      expect(undone.history.length, beforeLast.history.length, reason: 'history 长度');
      expect(undone.topPlayerId, beforeLast.topPlayerId);
      expect(undone.bottomPlayerId, beforeLast.bottomPlayerId);
      expect(undone.topWallsPlaced, beforeLast.topWallsPlaced);
      expect(undone.currentPlayerIsTop, beforeLast.currentPlayerIsTop);
      expect(undone.wallGrid, equals(beforeLast.wallGrid));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/surround_game/undo_test.dart`
Expected: FAIL —— `undoLastMove` 未定义。

- [ ] **Step 3: 实现 `undoLastMove`** —— 在 `game_ui_state.dart` 的 `GameController` 内（`cancelAction` 方法之后）新增：

```dart
  /// 悔棋：撤销最后一步（走棋或放墙），回合回到该步的执行者。
  ///
  /// 实现 = 用 replayHistory(history, upTo: length-1) 从历史前缀重建完整状态，
  /// 一次性恢复棋子位置/墙壁占用/墙计数/当前回合/validMoves/status。
  /// "悔棋"= 弹出历史栈顶 + 重放，无需逆操作。
  /// 空历史 → 无操作返回 false。重建一个干净 idle 的 GameUiState（清掉 pending）。
  bool undoLastMove() {
    final gs = state.gameState;
    if (gs.history.isEmpty) return false;
    final undone = QuoridorEngine.replayHistory(
      gs.history,
      upTo: gs.history.length - 1,
    );
    stateNotifier.value = GameUiState(gameState: undone);
    return true;
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/surround_game/undo_test.dart`
Expected: PASS（4 用例）。

- [ ] **Step 5: Commit**

```bash
git add lib/core/surround_game/game_ui_state.dart
git add -f test/core/surround_game/undo_test.dart
git commit -m "feat(surround_game): GameController.undoLastMove 悔棋 (单测 4)"
```
(Append trailer, two newlines before it:)
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>

---

## Task 2: `GamePage` 悔棋按钮 + 请求弹层 + widget smoke

**Files:**
- Modify: `lib/core/surround_game/pages/game_page.dart`
- Test: `test/core/surround_game/undo_test.dart`（追加 widget group）

- [ ] **Step 1: 写 widget smoke** —— 在 `undo_test.dart` 顶部加 import，并追加 widget group：

顶部 import 区追加：
```dart
import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/surround_game/pages/game_page.dart';
```

文件末尾（`main()` 内最后）追加：
```dart
  group('GamePage 悔棋按钮', () {
    testWidgets('渲染 悔棋 + 重新开始 按钮', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GamePage()));
      await tester.pump();
      expect(find.text('悔棋'), findsOneWidget);
      expect(find.text('重新开始'), findsOneWidget);
      expect(find.byIcon(Icons.undo), findsOneWidget);
    });
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/surround_game/undo_test.dart`
Expected: FAIL —— `find.text('悔棋')` 找不到（按钮还没加）。

- [ ] **Step 3a: 改底部按钮区** —— 在 `game_page.dart` 找到现有的"底部重来按钮"整段（`// 底部重来按钮 — 左下角` 开始的那个 `Align`，含单个 `GestureDetector` + 内部 `Row[refresh + 重新开始]`），整段替换为：

```dart
                // 底部操作 — 左下角：悔棋 | 重新开始
                ValueListenableBuilder<GameUiState>(
                  valueListenable: _controller.stateNotifier,
                  builder: (_, ui, __) {
                    final canUndo = ui.gameState.status == GameStatus.running &&
                        ui.gameState.history.isNotEmpty;
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 16, top: 6, bottom: 6, right: 16,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _bottomAction(
                              icon: Icons.undo,
                              label: '悔棋',
                              theme: theme,
                              onTap: canUndo
                                  ? () => _showUndoRequestConfirm(context, theme)
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            _bottomAction(
                              icon: Icons.refresh,
                              label: '重新开始',
                              theme: theme,
                              onTap: () => _showResetConfirm(context, theme),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
```

- [ ] **Step 3b: 加 `_bottomAction` 辅助方法** —— 在 `_GamePageState` 内（`_showResetConfirm` 之前）新增：

```dart
  /// 底部小操作项：图标 + 文字，onTap=null 时置灰禁用。
  Widget _bottomAction({
    required IconData icon,
    required String label,
    required BoardThemeData theme,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    final color = theme.btnText.withValues(alpha: enabled ? 0.5 : 0.25);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
```

- [ ] **Step 3c: 加 `_showUndoRequestConfirm` 弹层** —— 在 `_GamePageState` 内（`_showResetConfirm` 之后）新增（仿其结构）：

```dart
  void _showUndoRequestConfirm(BuildContext context, BoardThemeData theme) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: theme.panelBg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(Icons.undo, size: 32, color: theme.btnText.withValues(alpha: 0.6)),
            const SizedBox(height: 8),
            Text('对方请求悔棋',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: theme.btnText,
              ),
            ),
            const SizedBox(height: 4),
            Text('将撤销上一步，回合回到上一步的执行者',
              style: TextStyle(fontSize: 13, color: theme.btnSub),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      side: BorderSide(color: theme.btnBorder),
                    ),
                    child: Text('拒绝', style: TextStyle(color: theme.btnText)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _controller.undoLastMove();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: theme.piecePlayerA,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: const Text('同意', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/core/surround_game/undo_test.dart`
Expected: PASS（4 控制器 + 1 widget = 5）。

- [ ] **Step 5: analyze**

Run: `flutter analyze lib/core/surround_game/pages/game_page.dart lib/core/surround_game/game_ui_state.dart` → 期望无新增 issue（既有 info 可忽略）。

- [ ] **Step 6: Commit**

```bash
git add lib/core/surround_game/pages/game_page.dart test/core/surround_game/undo_test.dart
git commit -m "feat(surround_game): GamePage 悔棋按钮 + 请求弹层 (widget smoke 1)"
```
(Append trailer, two newlines before it:)
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>

---

## Task 3: 全量回归 + 验收

**Files:** 无（仅验证）

- [ ] **Step 1: analyze 全模块**

Run: `flutter analyze lib/core/surround_game` → 确认无新增 issue（既有 15 个 info 均为预存：`dangling_library_doc_comments`/`unnecessary_underscores`/`unnecessary_brace_in_string_interps`，不在本功能文件）。

- [ ] **Step 2: 回归相关测试**

Run: `flutter test test/core/surround_game/undo_test.dart test/core/surround_game/game_engine_test.dart test/core/surround_game/game_state_test.dart test/core/surround_game/replay_controller_test.dart test/core/surround_game/replay_page_test.dart` → 全绿（undo 5 + engine 35 + state 6 + replay_controller 9 + replay_page 2 = 57）。不跑 `game_ui_state_test.dart`（预存 wallColor 编译失败，无关）。

- [ ] **Step 3: 验收记录**

汇总：改动文件、commit 列表、analyze 结果、测试通过数；标注 `game_ui_state_test.dart` 预存失败为待办清理（范围外）。

---

## Self-Review

**1. Spec 覆盖：**
- §4 控制器 `undoLastMove` → Task 1 ✅
- §5 悔棋按钮 + 请求弹层 + 启用条件 → Task 2 ✅
- §6 测试（控制器 4 + widget smoke）→ Task 1/2 ✅
- §10 不在范围（LAN/批量/终局入口/wallColor 修复）→ 均未做 ✅

**2. 占位扫描：** 无 TBD/TODO；每步含可执行代码或命令。

**3. 类型/命名一致：** `undoLastMove`、`_showUndoRequestConfirm`、`_bottomAction`、`canUndo` 跨任务一致；复用 `replayHistory`、`GameUiState(gameState:)`、`_showResetConfirm` 既有范式。

**4. 测试设计：** 控制器用例通过 `stateNotifier.value =` 注入引擎构造的状态，绕开触摸坐标模拟与 `game_ui_state_test.dart` 的预存失败，断言真实（history 长度/回合/墙计数/墙位/多步等价）。widget smoke 仅断言按钮渲染（完整走子→悔棋流因需触摸坐标，留给手动验收；悔棋正确性由控制器测试承载）。
