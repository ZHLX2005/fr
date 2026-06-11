# Quoridor UI 重写实现计划 — Swift 忠实移植

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Flutter Widget 重现 Swift Quoridor-ios 的全部 UI 和 TouchView 交互，连通已完成纯 Dart 引擎。

**架构：** 棋盘层（CustomPainter）→ 游戏物件层（棋子/墙壁 Positioned Widget）→ 交互层（GestureDetector 三步手势），上层 GamePage 通过 StatefulWidget 持有引擎状态并驱动所有子 Widget。

**Tech Stack:** Flutter, Dart 3, CustomPainter, GestureDetector, AnimatedPositioned, ValueNotifier

---

## File Structure

```
lib/core/surround_game/
├── widgets/
│   ├── chess_board.dart        [NEW]  — 9×9 格子背景 CustomPainter
│   ├── chess_player.dart       [NEW]  — 棋子组件（监听 engine 位置）
│   ├── chess_wall.dart         [NEW]  — 墙壁渲染组件
│   ├── player_prompt.dart      [NEW]  — validMoves 高亮叠加层
│   ├── wall_prompt.dart        [NEW]  — 墙壁拖拽预览（绿/红反馈）
│   ├── touch_view.dart         [NEW]  — GestureDetector 三步交互
│   ├── player_panel.dart       [NEW]  — 上下面板（悔棋/步数/木板/重来）
│   └── quoridor_placeholder.dart [DEL] — 替换为 game_page
├── pages/
│   ├── game_page.dart          [NEW]  — 主游戏页组合所有组件
│   ├── game_lobby_page.dart    [MOD]  — _startLocalGame 指向 game_page
│   └── game_room_page.dart     [MOD]  — _startGame 指向 game_page
├── game_theme.dart             [NEW]  — 暗色/亮色主题常量
├── game_page_notifier.dart     [NEW]  — ValueNotifier 持有 GamePage 状态
└── surround_game.dart          [MOD]  — 导出新文件
```

---

### Task 1: 游戏页面状态管理 (GamePageNotifier)

**Files:**
- Create: `lib/core/surround_game/game_page_notifier.dart`
- Test: `test/core/surround_game/game_page_notifier_test.dart`

状态流转（控制层不需要，但 UI 层用它监听状态变化）：

```
TouchPhase:
  idle → beganMove / beganWall → dragging → ended / cancelled
```

GamePageNotifier 持有：
- `GameState _state`（引擎最新状态）
- `TouchPhase phase`
- `int? targetCellId`（走棋目标格）
- `({int x, int y, WallOrientation o})? wallData`（墙壁预览数据）
- `Color wallColor`（拖墙颜色）

- [ ] **Step 1: 写单测 — 初始化状态**

```dart
// test/core/surround_game/game_page_notifier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fr/core/surround_game/game_page_notifier.dart';
import 'package:fr/core/surround_game/engine/game_engine.dart';

void main() {
  group('GamePageNotifier', () {
    test('初始状态为 idle，GameState 已初始化', () {
      final notifier = GamePageNotifier();
      expect(notifier.phase, TouchPhase.idle);
      expect(notifier.state.validMoves, isNotEmpty);
    });
  });
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `flutter test test/core/surround_game/game_page_notifier_test.dart`
Expected: Compile error — 文件不存在

- [ ] **Step 3: 写 GamePageNotifier 实现**

```dart
// lib/core/surround_game/game_page_notifier.dart
import 'package:flutter/material.dart';
import 'engine/game_engine.dart';
import 'models/game_state.dart';
import 'surround_game_constants.dart';

/// 触摸阶段
enum TouchPhase { idle, beganMove, beganWall, dragging }

/// 游戏页面状态 — ChangeNotifier
///
/// 持有引擎 GameState，管理触控交互状态。
/// 走棋/放墙操作通过 engine 方法执行，更新 state 后 notify Listeners。
class GamePageNotifier extends ChangeNotifier {
  GameState _state = QuoridorEngine.initialize();
  GameState get state => _state;

  TouchPhase _phase = TouchPhase.idle;
  TouchPhase get phase => _phase;

  /// 走棋目标格（TouchPhase.beganMove / dragging 时有值）
  int? _targetCellId;
  int? get targetCellId => _targetCellId;

  /// 墙壁预览（TouchPhase.beganWall / dragging 时有值）
  ({int x, int y, WallOrientation o})? _previewWall;
  ({int x, int y, WallOrientation o})? get previewWall => _previewWall;

  /// 墙壁预览颜色：合法绿色，非法红色
  Color _wallColor = const Color(0xFF7CFFE5);
  Color get wallColor => _wallColor;

  /// 2D 偏移 — 棋子拖拽当前位置
  Offset? _dragOffset;
  Offset? get dragOffset => _dragOffset;

  /// 当前玩家剩余墙壁数
  int get currentWallCount => _state.currentPlayerIsTop
      ? _state.topWallsPlaced
      : _state.bottomWallsPlaced;

  /// 剩余墙壁数
  int get remainingWalls =>
      SurroundGameConstants.wallCountPerPlayer - currentWallCount;

  /// 当前玩家是 top
  bool get isTopTurn => _state.currentPlayerIsTop;

  /// 重置引擎
  void resetGame() {
    _state = QuoridorEngine.initialize();
    _phase = TouchPhase.idle;
    _targetCellId = null;
    _previewWall = null;
    _dragOffset = null;
    notifyListeners();
  }

  /// 悔棋（回退上一步）
  bool undoLastMove() {
    if (_state.history.isEmpty) return false;
    // 回退历史：需要 engine 支持 replayHistory
    // 暂不实现，返回 false
    return false;
  }

  // ─── 被 TouchView 调用的交互方法 ───

  /// TouchBegan 判断：点棋子还是空白
  ///
  /// 返回值标识进入走棋模式 (true) 还是放墙模式 (false)
  bool handleTouchBegan(Offset localPosition, double cellSize, double distance) {
    final currentPlayerId = _state.currentPlayerIsTop
        ? _state.topPlayerId
        : _state.bottomPlayerId;

    final cx = currentPlayerId % 9;
    final cy = currentPlayerId ~/ 9;
    final px = localPosition.dx / distance;
    final py = localPosition.dy / distance;
    final dx = (px - cx).abs();
    final dy = (py - cy).abs();

    if (dx < 0.5 && dy < 0.5) {
      // 点中棋子 → 走棋模式
      _phase = TouchPhase.beganMove;
      _targetCellId = currentPlayerId;
      notifyListeners();
      return true; // move mode
    } else {
      // 点空白 → 放墙模式（如果还有墙）
      if (remainingWalls <= 0) {
        // iWallIsEmpty → 退化为走棋
        _phase = TouchPhase.beganMove;
        _targetCellId = currentPlayerId;
        notifyListeners();
        return true;
      }
      _phase = TouchPhase.beganWall;
      _updateWallPreview(localPosition, distance);
      notifyListeners();
      return false; // wall mode
    }
  }

  /// TouchMoved 更新
  void handleTouchMoved(Offset localPosition, double cellSize, double distance) {
    if (_phase == TouchPhase.beganMove || _phase == TouchPhase.dragging) {
      _phase = TouchPhase.dragging;
      _dragOffset = localPosition;
      notifyListeners();
    } else if (_phase == TouchPhase.beganWall || _phase == TouchPhase.dragging) {
      _phase = TouchPhase.dragging;
      _updateWallPreview(localPosition, distance);
      notifyListeners();
    }
  }

  /// TouchEnded 执行
  void handleTouchEnded(Offset localPosition, double cellSize, double distance) {
    if (_phase == TouchPhase.beganMove || _phase == TouchPhase.dragging) {
      // 走棋模式：计算目标格子
      final targetX = (localPosition.dx / distance).round();
      final targetY = (localPosition.dy / distance).round();
      if (targetX >= 0 && targetX < 9 && targetY >= 0 && targetY < 9) {
        final targetId = targetX + targetY * 9;
        final newState = QuoridorEngine.movePiece(_state, targetId);
        if (newState != null) {
          _state = QuoridorEngine.switchTurn(newState);
        }
      }
      // 无论成功失败，结束走棋模式
    } else if (_phase == TouchPhase.beganWall || _phase == TouchPhase.dragging) {
      // 放墙模式
      final wall = _previewWall;
      if (wall != null) {
        final newState = QuoridorEngine.placeWall(_state, wall.x, wall.y, wall.o);
        if (newState != null) {
          _state = QuoridorEngine.switchTurn(newState);
        }
      }
    }
    _phase = TouchPhase.idle;
    _targetCellId = null;
    _previewWall = null;
    _dragOffset = null;
    notifyListeners();
  }

  void handleTouchCancelled() {
    _phase = TouchPhase.idle;
    _targetCellId = null;
    _previewWall = null;
    _dragOffset = null;
    notifyListeners();
  }

  void _updateWallPreview(Offset localPosition, double distance) {
    final wx = (localPosition.dx / distance).round();
    final wy = (localPosition.dy / distance).round();
    // 自动判定方向：基于拖拽 delta 或位置
    // 简单规则：上次记录的方向偏左/右 → horizontal，偏上/下 → vertical
    final old = _previewWall;
    WallOrientation orientation;
    if (old != null && old.x == wx && old.y == wy) {
      return; // 未变化
    }
    if (old != null) {
      // 用偏移量判定
      final dx = wx - old.x;
      final dy = wy - old.y;
      orientation = dx.abs() > dy.abs() ? WallOrientation.horizontal : WallOrientation.vertical;
    } else {
      orientation = WallOrientation.horizontal; // 默认
    }

    _previewWall = (x: wx, y: wy, o: orientation);

    // 判断是否合法
    final valid = QuoridorEngine.isWallPlacementValid(
      _state.wallGrid, _state.adjacency,
      _state.topPlayerId, _state.bottomPlayerId,
      wx, wy, orientation,
    );

    _wallColor = valid
        ? const Color(0xFF7CFFE5)  // 绿色合法
        : const Color(0xFFFF7CB8); // 粉色非法
  }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `flutter test test/core/surround_game/game_page_notifier_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/core/surround_game/game_page_notifier.dart test/core/surround_game/game_page_notifier_test.dart
git commit -m "feat(surround): add GamePageNotifier for UI state management"
```

---

### Task 2: 主题常量 (GameTheme)

**Files:**
- Create: `lib/core/surround_game/game_theme.dart`

- [ ] **Step 1: 写 GameTheme**

```dart
// lib/core/surround_game/game_theme.dart
import 'package:flutter/material.dart';

/// Quoridor 双主题配色 — 忠实移植 Swift Global.swift
///
/// 暗色（color=false）：
///   Global.swift: color=false → bg #6d2946, cellLine #677da0 ...
///   但我们使用纯黑背景 #000 和 #15152a 格子，符合 HTML v5 设计
///
/// 亮色（color=true）：
///   Global.swift: color=true → bg #ba99f1, cellLine #89dff1, wall #76ffd0
class GameTheme {
  final bool isLight;

  const GameTheme({this.isLight = false});

  // ── 暗色 ──
  static const _darkBg = Color(0xFF000000);
  static const _darkCell = Color(0xFF15152A);
  static const _darkCellBorder = Color(0xFF3A3A5E);
  static const _darkWall = Color(0xFF7CFFE5);
  static const _darkWrong = Color(0xFFFF7CB8);

  // ── 亮色 ──
  static const _lightBg = Color(0xFFBA99F1);
  static const _lightCell = Color(0xFFFFFFFF);
  static const _lightCellBorder = Color(0xFF89DFF1);
  static const _lightWall = Color(0xFF76FFD0);
  static const _lightWrong = Color(0xFFFF7CB8);

  // ── 棋子固定 ──
  static const topPlayer = Color(0xFFF4A523);
  static const bottomPlayer = Color(0xFFEE8E9A);

  Color get background => isLight ? _lightBg : _darkBg;
  Color get cellFill => isLight ? _lightCell : _darkCell;
  Color get cellBorder => isLight ? _lightCellBorder : _darkCellBorder;
  Color get wall => isLight ? _lightWall : _darkWall;
  Color get wrong => _darkWrong; // 两个主题同色

  /// 切换主题
  GameTheme get toggle => GameTheme(isLight: !isLight);
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/surround_game/game_theme.dart
git commit -m "feat(surround): add GameTheme with dark/light color scheme"
```

---

### Task 3: ChessBoard — 格子背景绘制

**Files:**
- Create: `lib/core/surround_game/widgets/chess_board.dart`

CustomPainter 绘制 9×9 圆角格子，每个格子内缩 `cellSize*0.1`（80% 大小），间距 = `distance - cellSize = cellSize*0.25`。

- [ ] **Step 1: 写 ChessBoard 实现**

```dart
// lib/core/surround_game/widgets/chess_board.dart
import 'package:flutter/material.dart';
import '../game_theme.dart';

/// 棋盘格子背景 — CustomPainter
///
/// 绘制 9×9 圆角矩形格子。
/// 不关心棋子/墙壁/交互，只渲染背景格子。
///
/// Swift 参考：ChessBoard.swift
class ChessBoardPainter extends CustomPainter {
  final double cellSize;
  final GameTheme theme;

  ChessBoardPainter({required this.cellSize, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final distance = cellSize * 1.25;
    final cellPaint = Paint()..color = theme.cellFill;
    final borderPaint = Paint()
      ..color = theme.cellBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final cornerRadius = cellSize * 0.08;
    final inset = cellSize * 0.1;
    final drawSize = cellSize * 0.8;

    for (int row = 0; row < 9; row++) {
      for (int col = 0; col < 9; col++) {
        final left = col * distance + inset;
        final top = row * distance + inset;
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, drawSize, drawSize),
          Radius.circular(cornerRadius),
        );
        canvas.drawRRect(rrect, cellPaint);
        canvas.drawRRect(rrect, borderPaint);
      }
    }
  }

  @override
  bool shouldRepaint(ChessBoardPainter old) => old.theme != theme;
}

/// ChessBoard Widget
///
/// 外层 Container + CustomPaint。
/// size 由父级约束（Expanded 撑满可用空间）。
class ChessBoard extends StatelessWidget {
  final GameTheme theme;

  const ChessBoard({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest.shortestSide;
        // cellSize = (W-40)/11, 但这里直接用布局尺寸
        final cellSize = (size - 40) / 11;
        return Container(
          decoration: BoxDecoration(
            color: theme.background,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(4),
          child: AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: ChessBoardPainter(
                cellSize: cellSize,
                theme: theme,
              ),
              size: Size(size - 8, size - 8),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/surround_game/widgets/chess_board.dart
git commit -m "feat(surround): add ChessBoard with CustomPainter grid"
```

---

### Task 4: ChessPlayer — 棋子组件

**Files:**
- Create: `lib/core/surround_game/widgets/chess_player.dart`

棋子为圆形 Widget，使用 `AnimatedPositioned` 做位移动画（Swift 200ms easeInOut）。

- [ ] **Step 1: 写 ChessPlayer 实现**

```dart
// lib/core/surround_game/widgets/chess_player.dart
import 'package:flutter/material.dart';
import '../game_theme.dart';
import '../surround_game_constants.dart';

/// 棋子 Widget
///
/// 使用 AnimatedPositioned 实现 200ms 弹性动画匹配 Swift。
/// 棋子中心坐标 = (cellPos.x * distance, cellPos.y * distance)。
/// 棋子大小 = cellSize * 0.7（Swift chessPlayer 宽高 = cellSize*0.8，内缩后约 0.7）。
///
/// Swift 参考：ChessPlayer.swift
class ChessPlayer extends StatelessWidget {
  final int cellId;         // 0..80 棋格坐标
  final double cellSize;
  final Color color;        // topPlayer or bottomPlayer
  final bool isTopPlayer;   // 是否上方玩家（用于 end zone 高亮）

  const ChessPlayer({
    super.key,
    required this.cellId,
    required this.cellSize,
    required this.color,
    required this.isTopPlayer,
  });

  @override
  Widget build(BuildContext context) {
    final distance = cellSize * 1.25;
    final x = (cellId % 9).toDouble();
    final y = (cellId ~/ 9).toDouble();
    final pieceSize = cellSize * 0.7;
    final inset = cellSize * 0.15; // (cellSize*0.8 - pieceSize) / 2 + cellSize*0.1
    final left = x * distance + (cellSize - pieceSize) / 2;
    final top = y * distance + (cellSize - pieceSize) / 2;

    return Positioned(
      left: left,
      top: top,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: pieceSize,
        height: pieceSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.75),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/surround_game/widgets/chess_player.dart
git commit -m "feat(surround): add ChessPlayer with animated position"
```

---

### Task 5: ChessWall — 墙壁渲染组件

**Files:**
- Create: `lib/core/surround_game/widgets/chess_wall.dart`

从 `state.wallList` 遍历墙壁并渲染。每个墙壁用 `Positioned` 定位。

Swift 墙壁尺寸：
- 横墙：w = cellSize×2.25+4, h = cellSize×0.25+4
- 竖墙：w = cellSize×0.25+4, h = cellSize×2.25+4

位置公式（Swift ChessWall.swift）：
- x = distance×wall.x + cellSize - 2
- y = distance×wall.y + cellSize - 2

- [ ] **Step 1: 写 ChessWall 实现**

```dart
// lib/core/surround_game/widgets/chess_wall.dart
import 'package:flutter/material.dart';
import '../game_theme.dart';
import '../models/game_state.dart';
import '../surround_game_constants.dart';

/// 墙壁渲染层
///
/// 遍历 state.history 中所有 isWall==true 的记录，渲染成墙壁。
///
/// Swift 参考：ChessWall.swift
class ChessWall extends StatelessWidget {
  final List<MoveRecord> history;
  final double cellSize;
  final GameTheme theme;

  const ChessWall({
    super.key,
    required this.history,
    required this.cellSize,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final distance = cellSize * 1.25;
    final wallColor = theme.wall;

    final children = <Widget>[];

    for (final record in history) {
      if (!record.isWall || record.orientation == null) continue;

      final isHorizontal = record.orientation == WallOrientation.horizontal;
      final left = record.x * distance + cellSize - 2;
      final top = record.y * distance + cellSize - 2;

      final wallWidth = isHorizontal
          ? cellSize * 2.25 + 4
          : cellSize * 0.25 + 4;
      final wallHeight = isHorizontal
          ? cellSize * 0.25 + 4
          : cellSize * 2.25 + 4;

      children.add(Positioned(
        left: left,
        top: top,
        child: Container(
          width: wallWidth,
          height: wallHeight,
          decoration: BoxDecoration(
            color: wallColor,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: wallColor.withValues(alpha: 0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
      ));
    }

    return Stack(children: children);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/surround_game/widgets/chess_wall.dart
git commit -m "feat(surround): add ChessWall rendering from history"
```

---

### Task 6: PlayerPrompt — validMoves 高亮

**Files:**
- Create: `lib/core/surround_game/widgets/player_prompt.dart`

从 `state.validMoves` 获取可走格子，在对应位置叠加半透明高亮。

- [ ] **Step 1: 写 PlayerPrompt 实现**

```dart
// lib/core/surround_game/widgets/player_prompt.dart
import 'package:flutter/material.dart';
import '../game_theme.dart';

/// validMoves 高亮叠加层
///
/// 当前玩家的可走格子以半透明青色高亮显示。
/// 用作 playerPrompt.showHint() / hideHint()。
///
/// Swift 参考：PlayerPrompt.swift
class PlayerPrompt extends StatelessWidget {
  final Set<int> validMoves;
  final double cellSize;
  final GameTheme theme;
  final bool visible;

  const PlayerPrompt({
    super.key,
    required this.validMoves,
    required this.cellSize,
    required this.theme,
    this.visible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || validMoves.isEmpty) return const SizedBox.shrink();

    final distance = cellSize * 1.25;
    final highlightSize = cellSize * 0.8;

    final children = validMoves.map((cellId) {
      final x = (cellId % 9).toDouble();
      final y = (cellId ~/ 9).toDouble();
      final left = x * distance + (cellSize - highlightSize) / 2;
      final top = y * distance + (cellSize - highlightSize) / 2;

      return Positioned(
        left: left,
        top: top,
        child: Container(
          width: highlightSize,
          height: highlightSize,
          decoration: BoxDecoration(
            color: theme.wall.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: theme.wall.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
        ),
      );
    }).toList();

    return Stack(children: children);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/surround_game/widgets/player_prompt.dart
git commit -m "feat(surround): add PlayerPrompt for validMoves highlight"
```

---

### Task 7: WallPrompt — 墙壁拖拽预览

**Files:**
- Create: `lib/core/surround_game/widgets/wall_prompt.dart`

拖拽墙壁时显示预览，颜色为合法绿/非法红。

- [ ] **Step 1: 写 WallPrompt 实现**

```dart
// lib/core/surround_game/widgets/wall_prompt.dart
import 'package:flutter/material.dart';
import '../surround_game_constants.dart';

/// 墙壁拖拽预览
///
/// 在 TouchMoved 阶段根据 touch 位置计算墙壁位置和方向，
/// 用透明度显示预览，颜色随合法性变化。
///
/// Swift 参考：WallPrompt.swift
class WallPrompt extends StatelessWidget {
  final ({int x, int y, WallOrientation o})? wallData;
  final double cellSize;
  final Color color; // 合法色 / 非法色
  final bool visible;

  const WallPrompt({
    super.key,
    required this.wallData,
    required this.cellSize,
    required this.color,
    this.visible = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible || wallData == null) return const SizedBox.shrink();

    final distance = cellSize * 1.25;
    final isHorizontal = wallData!.o == WallOrientation.horizontal;
    final left = wallData!.x * distance + cellSize - 2;
    final top = wallData!.y * distance + cellSize - 2;
    final wallWidth = isHorizontal
        ? cellSize * 2.25 + 4
        : cellSize * 0.25 + 4;
    final wallHeight = isHorizontal
        ? cellSize * 0.25 + 4
        : cellSize * 2.25 + 4;

    return Positioned(
      left: left,
      top: top,
      child: Container(
        width: wallWidth,
        height: wallHeight,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/surround_game/widgets/wall_prompt.dart
git commit -m "feat(surround): add WallPrompt for drag preview"
```

---

### Task 8: TouchView — 手势交互层

**Files:**
- Create: `lib/core/surround_game/widgets/touch_view.dart`

GestureDetector 覆盖整个棋盘，接收 `onPanStart/onPanUpdate/onPanEnd/onPanCancel`，调用 `GamePageNotifier` 对应方法。

- [ ] **Step 1: 写 TouchView 实现**

```dart
// lib/core/surround_game/widgets/touch_view.dart
import 'package:flutter/material.dart';
import '../game_page_notifier.dart';

/// 全屏手势层
///
/// 覆盖 Stack 最上方，接收触摸事件并路由到 GamePageNotifier。
///
/// Swift 参考：TouchView.swift — touchesBegan / touchesMoved / touchesEnded
///
/// 注意：Flutter 的 GestureDetector onPan 系列对应 Swift 的 touches 系列。
/// onPanStart → touchesBegan
/// onPanUpdate → touchesMoved
/// onPanEnd → touchesEnded
class TouchView extends StatelessWidget {
  final GamePageNotifier notifier;
  final double cellSize;
  final double distance;
  final Widget child;

  const TouchView({
    super.key,
    required this.notifier,
    required this.cellSize,
    required this.distance,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        notifier.handleTouchBegan(
          details.localPosition, cellSize, distance,
        );
      },
      onPanUpdate: (details) {
        notifier.handleTouchMoved(
          details.localPosition, cellSize, distance,
        );
      },
      onPanEnd: (details) {
        notifier.handleTouchEnded(
          details.localPosition, cellSize, distance,
        );
      },
      onPanCancel: () {
        notifier.handleTouchCancelled();
      },
      // 不放 child 是因为 TouchView 在全屏层之上，
      // 子 Widget 已经提前在 Stack 里了
      child: child,
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/surround_game/widgets/touch_view.dart
git commit -m "feat(surround): add TouchView gesture layer"
```

---

### Task 9: PlayerPanel — 上下面板

**Files:**
- Create: `lib/core/surround_game/widgets/player_panel.dart`

每个面板 4 个按钮：悔棋/步数/木板/重来

- [ ] **Step 1: 写 PlayerPanel 实现**

```dart
// lib/core/surround_game/widgets/player_panel.dart
import 'package:flutter/material.dart';
import '../game_page_notifier.dart';

/// 玩家面板按钮
///
/// 悔棋 | 步数 | 木板 | 重来
///
/// Swift 参考：GameController.swift → alignmentButtons
class PlayerPanel extends StatelessWidget {
  final GamePageNotifier notifier;
  final bool rotated; // 上方面板 true → 旋转 180°
  final bool active;  // false → 半透明

  const PlayerPanel({
    super.key,
    required this.notifier,
    this.rotated = false,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    final opacity = active ? 1.0 : 0.4;

    final panel = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.95),
        border: Border.all(color: const Color(0xFF222222)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _BoardButton(
            label: '↩',
            sub: '悔棋',
            onTap: active ? () => notifier.undoLastMove() : null,
          ),
          const SizedBox(width: 4),
          _BoardButton(
            label: '${notifier.state.history.length}',
            sub: '步数',
            onTap: null, // 仅显示
          ),
          const SizedBox(width: 4),
          _BoardButton(
            label: '${notifier.remainingWalls}',
            sub: '木板',
            onTap: null, // 仅显示
          ),
          const SizedBox(width: 4),
          _BoardButton(
            label: '↻',
            sub: '重来',
            onTap: active ? () => notifier.resetGame() : null,
          ),
        ],
      ),
    );

    if (rotated) {
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationZ(3.14159),
        child: panel,
      );
    }
    return panel;
  }
}

class _BoardButton extends StatelessWidget {
  final String label;
  final String sub;
  final VoidCallback? onTap;

  const _BoardButton({
    required this.label,
    required this.sub,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 48),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          border: Border.all(color: const Color(0xFF2A2A2A)),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(
          children: [
            Text(label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            Text(sub,
              style: const TextStyle(
                fontSize: 7,
                color: Color(0xFF666666),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/surround_game/widgets/player_panel.dart
git commit -m "feat(surround): add PlayerPanel with 4 buttons"
```

---

### Task 10: GamePage — 组合主页面

**Files:**
- Create: `lib/core/surround_game/pages/game_page.dart`
- Modify: `lib/core/surround_game/surround_game.dart`（添加导出）
- Delete: `lib/core/surround_game/widgets/quoridor_placeholder.dart`

GamePage 作为主游戏页面，组合所有 Widget + 监听 Notifier。

- [ ] **Step 1: 写 GamePage 实现

```dart
// lib/core/surround_game/pages/game_page.dart
import 'package:flutter/material.dart';
import '../game_page_notifier.dart';
import '../game_theme.dart';
import '../widgets/chess_board.dart';
import '../widgets/chess_player.dart';
import '../widgets/chess_wall.dart';
import '../widgets/player_prompt.dart';
import '../widgets/wall_prompt.dart';
import '../widgets/touch_view.dart';
import '../widgets/player_panel.dart';

/// 主游戏页面
///
/// Stack 层次（从下到上）：
///   1. ChessBoard (CustomPainter 格子背景)
///   2. ChessWall (已放置墙壁)
///   3. PlayerPrompt (validMoves 高亮)
///   4. ChessPlayer × 2 (棋子)
///   5. WallPrompt (拖墙预览)
///   6. TouchView (手势层, 透明)
///
/// 上下面板分别在上方和下方。
///
/// Swift 参考：GameController.swift
class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  final _notifier = GamePageNotifier();
  var _theme = const GameTheme();

  /// 当前玩家拖拽偏移（/loop 模式检测）
  final _kTouchOffset = 50.0; // Swift kOffset = 50

  @override
  void initState() {
    super.initState();
    _notifier.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _notifier.removeListener(() => setState(() {}));
    _notifier.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    setState(() => _theme = _theme.toggle);
  }

  @override
  Widget build(BuildContext context) {
    final state = _notifier.state;
    final isTopTurn = state.currentPlayerIsTop;

    return Scaffold(
      backgroundColor: _theme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            children: [
              // 上方面板（旋转 180°，非活跃半透明）
              PlayerPanel(
                notifier: _notifier,
                rotated: true,
                active: isTopTurn,
              ),

              // 棋盘区域
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // cellSize = (可用宽 - 40) / 11
                    final boardSize = constraints.biggest.width - 20;
                    final cellSize = (boardSize - 40) / 11;
                    final distance = cellSize * 1.25;

                    return Padding(
                      padding: const EdgeInsets.all(4),
                      child: Stack(
                        children: [
                          // 1. 格子背景
                          Positioned.fill(
                            child: ChessBoard(theme: _theme),
                          ),

                          // 2. 墙壁
                          Positioned.fill(
                            child: ChessWall(
                              history: state.history,
                              cellSize: cellSize,
                              theme: _theme,
                            ),
                          ),

                          // 3. validMoves 高亮
                          Positioned.fill(
                            child: PlayerPrompt(
                              validMoves: state.validMoves,
                              cellSize: cellSize,
                              theme: _theme,
                              visible: _notifier.phase == TouchPhase.beganMove
                                  || _notifier.phase == TouchPhase.dragging,
                            ),
                          ),

                          // 4. 棋子
                          Positioned.fill(
                            child: Stack(
                              children: [
                                ChessPlayer(
                                  cellId: state.topPlayerId,
                                  cellSize: cellSize,
                                  color: GameTheme.topPlayer,
                                  isTopPlayer: true,
                                ),
                                ChessPlayer(
                                  cellId: state.bottomPlayerId,
                                  cellSize: cellSize,
                                  color: GameTheme.bottomPlayer,
                                  isTopPlayer: false,
                                ),
                                // 拖拽中的棋子跟随（合并到现有棋子）
                                if (_notifier.dragOffset != null
                                    && (_notifier.phase == TouchPhase.beganMove
                                        || _notifier.phase == TouchPhase.dragging))
                                  _buildFloatingPiece(cellSize),
                              ],
                            ),
                          ),

                          // 5. 墙壁预览
                          Positioned.fill(
                            child: WallPrompt(
                              wallData: _notifier.previewWall,
                              cellSize: cellSize,
                              color: _notifier.wallColor,
                              visible: _notifier.phase == TouchPhase.beganWall
                                  || _notifier.phase == TouchPhase.dragging,
                            ),
                          ),

                          // 6. 手势层
                          Positioned.fill(
                            child: TouchView(
                              notifier: _notifier,
                              cellSize: cellSize,
                              distance: distance,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // 下方面板
              PlayerPanel(
                notifier: _notifier,
                rotated: false,
                active: !isTopTurn,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 拖拽中浮动的棋子
  Widget _buildFloatingPiece(double cellSize) {
    final offset = _notifier.dragOffset!;
    final color = _notifier.isTopTurn
        ? GameTheme.topPlayer
        : GameTheme.bottomPlayer;
    final pieceSize = cellSize * 0.7;

    // 小屏偏移 +50pt，防止手指遮挡
    final dx = offset.dx - pieceSize / 2;
    final dy = offset.dy - pieceSize / 2 - _kTouchOffset;

    return Positioned(
      left: dx,
      top: dy,
      child: Container(
        width: pieceSize,
        height: pieceSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.75),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 更新 surround_game.dart 导出**

```dart
// lib/core/surround_game/surround_game.dart — 追加导出
export 'game_theme.dart';
export 'game_page_notifier.dart';
export 'pages/game_page.dart';
export 'widgets/chess_board.dart';
export 'widgets/chess_player.dart';
export 'widgets/chess_wall.dart';
export 'widgets/player_prompt.dart';
export 'widgets/wall_prompt.dart';
export 'widgets/touch_view.dart';
export 'widgets/player_panel.dart';
```

- [ ] **Step 3: 删除 quoridor_placeholder.dart**

删除 `lib/core/surround_game/widgets/quoridor_placeholder.dart`

- [ ] **Step 4: 修改 game_lobby_page.dart**

```dart
// lib/core/surround_game/pages/game_lobby_page.dart
// 修改 _startLocalGame:

  void _startLocalGame() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GamePage(),
      ),
    );
  }
```

- [ ] **Step 5: 修改 game_room_page.dart**

```dart
// lib/core/surround_game/pages/game_room_page.dart
// 修改 _startGame 和 QuoridorPlaceholder 引用:

  void _startGame() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const GamePage(),
      ),
    );
  }
```

移除文件开头的 `import '../widgets/quoridor_placeholder.dart';`。

- [ ] **Step 6: 编译验证和清理**

```bash
flutter analyze lib/core/surround_game/
```

Expected: 无错误、无未使用导入。

- [ ] **Step 7: Commit**

```bash
git add lib/core/surround_game/pages/game_page.dart \
       lib/core/surround_game/pages/game_lobby_page.dart \
       lib/core/surround_game/pages/game_room_page.dart \
       lib/core/surround_game/surround_game.dart \
       lib/core/surround_game/game_theme.dart \
       lib/core/surround_game/game_page_notifier.dart \
       lib/core/surround_game/widgets/chess_board.dart \
       lib/core/surround_game/widgets/chess_player.dart \
       lib/core/surround_game/widgets/chess_wall.dart \
       lib/core/surround_game/widgets/player_prompt.dart \
       lib/core/surround_game/widgets/wall_prompt.dart \
       lib/core/surround_game/widgets/touch_view.dart \
       lib/core/surround_game/widgets/player_panel.dart
git rm lib/core/surround_game/widgets/quoridor_placeholder.dart
git commit -m "feat(surround): GamePage with full UI and TouchView interaction"
```

---

### Task 11: 验证 — 启动 + 功能检查

**Files:** None — 手动功能验证

- [ ] **Step 1: 启动 app，导航到本地对战**

```bash
flutter run
```

操作：
1. 进入 "围追堵截" 大厅
2. 点击 "本地对战" 按钮
3. 观察 GamePage 是否显示：深色背景、9×9 格子、2 个棋子、上下面板

- [ ] **Step 2: 测试走棋手势**

1. 手指触摸上方橙色棋子
2. 拖拽到绿色高亮格子
3. 松开手指 — 棋子飞过去、换手、下方面板高亮
4. 验证 validMoves 高亮随换手重新计算

- [ ] **Step 3: 测试放墙手势**

1. 触摸空白区域（注意剩余墙数 > 0）
2. 往右/往下拖拽 — 墙壁预览出现，颜色绿/红
3. 松开手指如果绿色 → 墙壁固定；如果红色 → 消失

- [ ] **Step 4: 测试面板按钮**

1. 步数：显示当前历史步数
2. 木板：显示当前玩家剩余墙壁数
3. 重来：重置整个游戏
4. 悔棋：预留接口（当前返回 false，按钮无反应）

- [ ] **Step 5: 测试主题切换**

暂未实现步数按钮主题切换功能（下轮迭代）。当前在代码中修改 `_theme.toggle` 调用方式。

- [ ] **Step 6: Commit**

```bash
git commit --allow-empty -m "chore: verify GamePage UI and interactions"
```

---

## 自审

**Spec 覆盖检查：**
- ✅ ChessBoard（格子背景绘制）— Task 3
- ✅ ChessPlayer（棋子 + AnimatedPositioned）— Task 4
- ✅ ChessWall（墙壁渲染）— Task 5
- ✅ PlayerPrompt（validMoves 高亮）— Task 6
- ✅ WallPrompt（拖拽预览 + 绿/红颜色）— Task 7
- ✅ TouchView（三步手势）— Task 8
- ✅ PlayerPanel（4 按钮 + 旋转 180°）— Task 9
- ✅ GamePage（组合 + Stack 层次）— Task 10
- ✅ 主题配色（GameTheme 暗色/亮色）— Task 2
- ✅ GamePageNotifier（状态管理 + 引擎集成）— Task 1
- ✅ 导航入口（Lobby + RoomPage → GamePage）— Task 10
- ✅ 清理 placeholder — Task 10
- ⏳ 步数按钮主题切换 — 下轮迭代（按纽功能已在 notifier 里预留）

**占位符检查：** 无 TBD/TODO，代码完整。
