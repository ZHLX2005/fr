# 双网格系统与 MVC 架构

## 双网格系统

Quoridor 最核心的设计决策是将棋盘划分为**两个独立的网格系统**：

### 棋子网格 (9×9)

`DataModel.swift:77-79` 定义了棋子坐标的编址方式：

```swift
// 来源: DataModel.swift:77-79
private func updateId() {
    id = x + y * 9
}
```

- 共有 81 个格子，编号 0-80
- 从左上角开始，x 为列(0-8)，y 为行(0-8)
- `gameNears` 数组 (`GameModel.swift:142`) 维护 81 个格子的邻接关系
- `player` 属性是 Bool 值，`true`=Top(上)，`false`=Down(下)

### 墙壁网格 (17×17)

每个墙壁覆盖 3 个格子。`DataModel.swift:82-94` 展示了墙壁编址：

```swift
// 来源: DataModel.swift:82-94
private func updateWallIds() {
    wallIds = []
    if t {
        for i in [-1,0,1] {
            var wallId = (x * 2 + 1) + (y * 2 + 1) * 17
            if h {
                wallId += i       // 横向墙壁：同一行，三列
            } else {
                wallId += (i * 17) // 竖向墙壁：同一列，三行
            }
            wallIds.append(wallId)
        }
    }
}
```

- 共有 289 个格子，编号 0-288
- `gameWalls` 布尔数组 (`GameModel.swift:145`) 标记每个格子是否被墙壁占用
- 墙壁的 (x,y) 坐标在 0-8 范围内（和棋子网格范围一致），通过 `(x*2+1) + (y*2+1)*17` 映射到 17×17 网格
- `h=true` 表示横向（占同一行三列），`h=false` 表示竖向（占同一列三行）

### 网格关系图解

```
棋子位置 (x=4, y=4)        横向墙壁 (x=4, y=4, h=true)
    ┌───┬───┬───┬───┬───┐          ───
    │   │   │   │   │   │    ║  ║  ║  ║  ║
    ├───┼───┼───┼───┼───┤    ║  ║  ║  ║  ║
    │   │   │ P │   │   │    ║  ║═══║  ║  ║     ← 墙壁占据3个墙格
    ├───┼───┼───┼───┼───┤    ║  ║  ║  ║  ║
    │   │   │   │   │   │    ║  ║  ║  ║  ║
    └───┴───┴───┴───┴───┘
    9×9 棋子网格                17×17 墙壁网格（简化示意）
```

## MVC 架构

引用 `README.md:35-38` 和 `GameController.swift` 的设计模式：

```
┌────────────────────────────────────────────────────────┐
│                     GameController                       │
│  (MVC-C: 接收触摸 → 路由到Model → 更新Views → AI)       │
├─────────────┬──────────────────────┬────────────────────┤
│    Model     │       Views          │    Controllers     │
│             │                      │                    │
│  GameModel  │  ChessBoard (9×9)    │  GameController    │
│  (单例)     │  ChessPlayer (棋子)  │  (主控制器)        │
│             │  ChessWall (墙壁)    │                    │
│  DataModel  │  WallPrompt (预览)   │  TouchView         │
│  (数据单元) │  PlayerPrompt (提示) │  (触摸路由)        │
│             │  Screen (回合控制)   │                    │
│  GameAi     │  EndScreen (结束)    │  FrameCalculator   │
│  (AI引擎)   │  Background (背景)   │  (坐标计算)        │
│             │  Demonstration (教程) │                    │
└─────────────┴──────────────────────┴────────────────────┘
```

### GameController 的数据流

`GameController.swift:198-213` 展示了触摸事件的完整路由：

```swift
// 来源: GameController.swift:198-213
func touchEnded(location: CGPoint, type: Bool) {
    if type {
        // 放置墙壁
        if let newWall = wallPrompt.endMove(location) {
            GameModel.shared.iPutWall(newWall)   // ← Model 更新
            changePlayer(true)                   // ← 换手
        }
    } else {
        // 移动棋子
        playerPrompt.hideHint()
        if let newId = FrameCalculator.playerDataFromTouch(location) {
            GameModel.shared.iMoveWithId(newId)  // ← Model 更新
            changePlayer(false)                  // ← 换手
        }
    }
}
```

`changePlayer()` 方法 (`GameController.swift:69-88`) 负责：

1. 更新画面（重绘墙壁或棋子）
2. 播放音效（`pushSound.play()`）
3. 更新屏幕遮罩（`updateScreen()`）
4. 更新按钮状态（`updateButtonsTitle()`）
5. 检查游戏状态并决定是否弹出结束画面
6. 触发 AI 运算（`aiPlay()`）

### 单例模式

`GameModel.swift:147-157` 确保了全局唯一的游戏状态：

```swift
// 来源: GameModel.swift:147-157
static var shared = GameModel()
private override init() {
    super.init()
    initModelData()
}
```

初始化 `initModelData()` (`GameModel.swift:161-173`) 负责：
- 放置棋子到起始位置：`topPlayer(4,0)`、`downPlayer(4,8)`
- 清空墙壁数组
- 随机决定先后手（`arcFirstPlayer()`）
- 初始化邻接图（`initGameNearsAndWalls()`）

## 坐标计算系统

`FrameCalculator.swift` 负责游戏坐标 ←→ 屏幕坐标的转换：

```
cellSize = (screenWidth - 40) / 11
distance = cellSize * 1.25
```

- `distance` 是相邻格子中心之间的距离
- `cellSize` 是每个格子的宽度（减去内边距后 ÷ 11 是因为 9 格 + 2 边距）
- 同一设备上 FrameCalculator 是单例，确保所有视图使用统一坐标

## 文件索引

| 文件 | 行数 | 核心职责 |
|------|------|---------|
| DataModel.swift | 110 | 棋子/墙壁的数据结构定义 |
| GameModel.swift | 219 | 游戏状态管理（单例） |
| GameModel+Action.swift | 105 | 墙壁放置/移除/悔棋 |
| GameModel+Logic.swift | 23 | 可移动范围计算 |
| GameAi.swift | 468 | AI 寻路与策略 |
| GameController.swift | 347 | 游戏流程控制 |
| FrameCalculator.swift | — | 坐标计算 |
| TouchView.swift | — | 触摸路由 |
