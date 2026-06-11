# Quoridor UI 重写设计 —— Swift 忠实移植

## 概述

本 spec 描述 Quoridor 游戏的 Flutter UI 重写设计。布局和交互忠实参考 [Quoridor-ios](https://github.com/Joke-Lin/Quoridor-ios) 的 Swift 实现，沿用已完成纯 Dart 引擎重构（Phase 1）导出的 `QuoridorEngine / QuoridorState` 接口。

## 布局系统

### 棋盘坐标系

基于 `FrameCalculator.swift`，坐标计算统一在 Widget 内部完成：

| 参数 | 公式 | 来源 |
|------|------|------|
| `cellSize` | `(screenW - 40) / 11` | ChessBoard.swift:16 |
| `distance` | `cellSize * 1.25` | ChessBoard.swift:17 |
| 棋子 frame | `(x*distance, y*distance, cellSize*0.8, cellSize*0.8)` | 同比缩放 |
| 横墙 frame | `(x*distance+cellSize-2, y*distance+cellSize-2, cellSize*2.25+4, cellSize*0.25+4)` | ChessWall.swift:22-23 |
| 竖墙 frame | `(x*distance+cellSize-2, y*distance+cellSize-2, cellSize*0.25+4, cellSize*2.25+4)` | ChessWall.swift:22-23 |

### Widget 结构

```
GamePage (StatefulWidget)
├── PlayerPanel (top, rotated 180°)
│   └── BoardButton × 4 (悔棋 / 步数 / 木板 / 重来)
├── Expanded(Stack)
│   ├── ChessBoard         — 9×9 格子背景，CustomPainter 绘制
│   ├── WallPrompt (layer) — 墙壁拖拽预览，仅拖墙时显示
│   ├── ChessWall (layer)  — 所有已放置墙壁
│   ├── PlayerPrompt       — validMoves 高亮叠加层
│   └── ChessPlayer × 2   — 棋子（橙色 top, 粉色 bottom）
├── TouchView (GestureDetector) — 手势捕获，覆盖整个棋盘
└── PlayerPanel (bottom)
    └── BoardButton × 4
```

`TouchView` 作为全屏手势层置于 `Stack` 最上方，通过 `onPanStart/onPanUpdate/onPanEnd` 实现 3 步交互。

## 棋盘绘制 (ChessBoard)

- 使用 `CustomPainter` 绘制 9×9 深色圆角矩形格子
- 格子间距 = `distance - cellSize = cellSize * 0.25`
- 支持暗色/亮色主题：`cellBg`, `cellBorder` 随主题切换
- 格子大小 = `cellSize * 0.8`（内边距 = `cellSize * 0.1`）

## 墙壁渲染 (ChessWall)

- 横墙：宽 `cellSize*2.25+4` × 高 `cellSize*0.25+4`，横跨 2 列
- 竖墙：宽 `cellSize*0.25+4` × 高 `cellSize*2.25+4`，横跨 2 行
- 墙壁圆角 2-3px，暗色 `#7cffe5`，亮色 `#76ffd0`
- 轻量发光阴影（对应 Swift 无阴影但保留视觉区分度）
- 遍历 `gameState.wallList` 渲染已放置墙壁

## 棋子 (ChessPlayer)

- 圆形，半径 = `cellSize * 0.35`
- 白色半透明边框（`border: 2.5px solid rgba(255,255,255,0.75)`）
- 玩家 1 (top)：橙色 `#f4a523`
- 玩家 2 (bottom)：粉色 `#ee8e9a`
- 移动动画：`AnimatedPositioned` + `Curves.easeInOut`，duration 200ms
- 落子/跳子时棋子用 `AnimatedContainer` 做位移动画

## 触控交互 (TouchView)

完全复刻 Swift `TouchView.swift` 的三步手势流程：

### Step 1: TouchBegan → 模式判断

```
触点在棋子区域 (cell 范围内) → touchType = false → 走棋模式
  └─ playerPrompt.showHint() → 高亮 validMoves
触点在空白区域 → touchType = true → 放墙模式
  └─ wallPrompt.add(location) → 墙壁预览出现
例外：玩家剩余木板 = 0（iWallIsEmpty）→ 空白默认为走棋模式
```

判断逻辑：触摸位置与当前玩家棋子位置的 `distance` 比较。若 `abs(dx) < 0.5 && abs(dy) < 0.5` 且距离 < 1 格 → 走棋模式。否则 → 放墙模式。

### Step 2: TouchMoved → 拖拽反馈

```
走棋模式：chessPlayer.move(location)
  └─ 棋子中心跟随手指
  └─ 小屏偏移 +50pt（kOffset = 50），防止手指遮挡
放墙模式：wallPrompt.move(location)
  └─ 自动判定横/竖（根据 drag delta 方向）
  └─ 合法位置：颜色 = kColor (绿色)   #7cffe5
  └─ 非法位置：颜色 = kWrongColor (粉红) #ff7cb8
```

自动判定横/竖：比较 `abs(dragDx)` 和 `abs(dragDy)`，大者方向为墙方向。

### Step 3: TouchEnded → 执行/取消

```
走棋模式：
  └─ playerPrompt.hideHint()
  └─ playerDataFromTouch(loc) → 计算目标 cellId
  └─ 目标在 validMoves 内 → engine.move(id) → 棋子飞过去
  └─ 不在 validMoves 内 → 棋子弹回原位
放墙模式：
  └─ wallPrompt.endMove(loc)
  └─ wallDataForTouch(loc) → 计算出 wall 坐标和方向
  └─ engine.iWallIsAllow() → 通过则 engine.putWall(data) → 墙壁固定
  └─ 不通过则 wallPrompt 消失
```

### TouchView 位置计算

```dart
// 触摸 → 棋子 cell 坐标
int cellIdFromTouch(Offset touch) {
  double x = (touch.dx - cellSize * 0.1) / distance;
  double y = (touch.dy - cellSize * 0.1) / distance;
  if (x < 0 || x >= 9 || y < 0 || y >= 9) return -1;
  return y.toInt() * 9 + x.toInt();
}

// 触摸 → 墙壁坐标（wall grid 17×17）
(int x, int y, bool horizon) wallDataFromTouch(Offset touch) {
  double wx = touch.dx / distance;
  double wy = touch.dy / distance;
  // ... 舍入到最近的墙格点
}
```

## 玩家面板 (PlayerPanel)

- 上方面板旋转 180°（`Transform.rotate`）
- 每面板 4 个按钮：悔棋 / 步数 / 木板 / 重来
- 只当前玩家面板有交互反馈（非活跃面板半透明）
- 步数按钮同时作为主题切换（`GameModel.shared.color` 切换）
- 按钮布局：`Row`，flex 均匀分布

## 配色方案

### 暗色（默认）

| 元素 | 色值 | Swift 源码引用 |
|------|------|---------------|
| 背景 | `#000000` | CGColor.black |
| 格子 | `#15152a` | ~#111 风格 |
| 格线 | `#3a3a5e` | global.cellLine |
| 横墙/竖墙 | `#7cffe5` | global.wall |
| Top 棋子 | `#f4a523` | global.Top |
| Bot 棋子 | `#ee8e9a` | global.Down |
| 错误/非法 | `#ff7cb8` | global.wrong |

### 亮色（切换）

| 元素 | 色值 |
|------|------|
| 背景 | `#ba99f1` |
| 格子 | `#ffffff` |
| 格线 | `#89dff1` |
| 墙壁 | `#76ffd0` |
| Top/Bot 棋子 | 同暗色 |
| 错误 | 同暗色 |

## 棋盘状态联动

| UI 组件 | 监听引擎状态 | 表现 |
|---------|------------|------|
| ChessBoard | `gameState.board` | 格子布局不变 |
| ChessPlayer | `gameState.player1.position`, `player2.position` | 棋子位置动画更新 |
| ChessWall | `gameState.wallList` | 墙壁增删刷新 |
| PlayerPrompt | `gameState.validMoves()` | 高亮棋子周边合法移动 |
| 木板计数 | `gameState.player1.wallCount`, `player2.wallCount` | 面板数字更新 |
| 步数计数 | `gameState.moveHistory.length` | 面板步数更新 |

## 误差状态

| 场景 | 表现 |
|------|------|
| 触摸区域外（wall 在非合法格） | 墙壁颜色变红，放手后消失 |
| 棋子移动到非法格 | 棋子弹回原位（AnimatedPositioned + reverse） |
| 墙壁放置被阻挡 | wallPrompt 消失，无变化 |
| 主题切换 | 格子/边框/墙壁颜色过渡动画（~300ms） |
| 面板按钮无墙可放 | 木板按钮显示 0 但可点击，engine 层面拒绝 |
| 非当前玩家操作 | TouchView 不响应手势（GestureDetector ignore） |

## 实现顺序

1. ChessBoard（格子背景绘制）
2. ChessPlayer（棋子 + 位移动画）
3. TouchView 手势框架（onPanStart/Update/End）
4. ChessWall（墙壁渲染 + 放置/移除动画）
5. PlayerPrompt（validMoves 高亮）
6. WallPrompt（拖拽预览）
7. PlayerPanel + 按钮逻辑
8. GamePage 组合 + 主题切换
9. 清理 _legacy UI 文件

## 非功能需求

- 所有 UI 组件 200-400 行，ChessBoard 使用 CustomPainter 而非 9×9 Widget 堆叠
- TouchView 逻辑与棋盘绘制分离，不混入 Painter
- 按钮回调使用 engine 接口而非直接操作 GameState
- 主题切换通过 `InheritedWidget` 或 `ValueNotifier` 传播
- 手势参数（kOffset = 50.0）提取为常量
