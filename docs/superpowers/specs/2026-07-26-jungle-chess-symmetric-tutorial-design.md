# 斗兽棋：全屏对称本地对战 + 规则教程

日期：2026-07-26
模块：`lib/core/jungle_chess/`

## 背景

现有斗兽棋本地对局页是单方向布局：`AppBar` + 顶部 `_TurnCard`（「🔵 蓝方走棋 / 第 N 回合 / N 步」）+ 棋盘。
两位玩家共用一台设备面对面坐时，上方（红方）玩家看到的所有文字与棋子都是倒的，回合信息、悔棋按钮也全在他够不着且读不了的一侧。

参照同项目的 `lib/core/surround_game/`（已是全屏对称热座布局），把斗兽棋改造成双方对称，并新增规则教程。

## 目标

1. 全屏对称布局：上下各一块玩家面板，上方面板整体旋转 180°。
2. 删除顶部回合卡与 AppBar，「轮到谁」由面板自身高亮表达。
3. 红方棋子的动物图标恒定旋转 180°，上方玩家看自己的棋子是正的。
4. 新增教程入口，在真实棋盘上逐步动画演示规则。

## 非目标

- 不改 `engine/jungle_engine.dart` 规则实现。
- 不做联机版本，不接 relay。
- 棋盘不整体旋转（已确认：只翻棋子图标，不翻棋盘）。

## 设计

### 1. 布局

```
SafeArea
├ JunglePlayerPanel(color: red,  rotated: true)    ← Matrix4.rotationZ(π)
├ Expanded → Center → AspectRatio(7/9) → JungleBoardFrame → JungleBoard
├ JunglePlayerPanel(color: blue, rotated: false)
└ 底部操作行：返回 · 重开 · 教程
```

面板内容（左→右）：颜色圆点 + 方名 + 存活子数 + 已吃子数 + 悔棋按钮。
悔棋按钮放在**各自面板内**，跟随面板旋转，两侧玩家都能触达且读得懂。
当前回合方：面板加彩色描边 + 淡色底；非当前方：整体降透明度。

底部操作行只对下方玩家正向（与 surround_game 一致）。

### 2. 棋子翻转

`JunglePieceWidget` 新增 `flipped` 参数。为 true 时只对内部 `Image.asset` 套
`Transform.rotate(angle: pi)`，圆盘底色与玩家色描边不旋转（旋转它们没有视觉意义）。
`JungleBoard` 对 `piece.color == PlayerColor.red` 传 `flipped: true`。

### 3. 棋盘复用

`JungleBoard` 做三处扩展，让正式对局与教程共用同一渲染：

| 参数 | 含义 |
|---|---|
| `touchController` 改为可空 | 为 null → 只读演示模式，不挂 GestureDetector |
| `highlightCells` | `Map<int, Color>`，教程用来点亮河流 / 陷阱 / 兽穴 |
| 棋子层 `AnimatedPositioned` | key 为 `ValueKey('${color}_${animal}')`，走子平滑位移 |

`AnimatedPositioned` 同时让正式对局的每一步都有位移动画（原来是瞬移）。
拖动中的棋子仍由 `_buildDraggingPiece` 单独用裸 `Positioned` 渲染，不受影响。

### 4. 教程

新增 `lib/core/jungle_chess/tutorial/`：

- **`tutorial_steps.dart`** — 纯数据常量，无 Flutter 依赖之外的逻辑：

  ```dart
  class TutorialMove   { Coord from, to; String caption; }
  class TutorialChapter{ String title, summary; List<Piece> setup;
                         List<TutorialMove> moves; Map<int, Color> highlights; }
  ```

  章节：
  1. 棋盘与目标 —— 河流 / 陷阱 / 兽穴高亮
  2. 基本走法 —— 上下左右一格
  3. 等级与吃子 —— 象>狮>虎>豹>狼>狗>猫>鼠
  4. 鼠吃象 · 象不吃鼠
  5. 鼠入河 —— 只有鼠能进河；鼠在河中不能吃岸上的象
  6. 狮虎跳河 —— 纵横跨河；河中有鼠时不能跳
  7. 陷阱降级 —— 进入对方陷阱等级归 0
  8. 入穴取胜 —— 进入对方兽穴即胜；不能进自己的兽穴

- **`tutorial_page.dart`** — 独立路由（自带 AppBar）。持有 `_TutorialController`
  （`ChangeNotifier`：当前章节 / 当前步 / 派生 `GameState`）。
  顶部章节横向 chip 列表，中部只读 `JungleBoard`，底部说明文字 + 上一步/播放/下一步。
  演示走子直接调 `JungleEngine.movePiece`，规则说明与真实规则不会漂移。

  播放状态由 `Timer.periodic` 驱动，`dispose` 时取消。

### 5. 胜负覆盖层

替换 `showJungleGameOverDialog` 的单向弹窗为页面内 `Stack` 覆盖层：
胜者文案渲染两份，上半部分旋转 180°、下半部分正向，中间放「再来一局 / 退出」按钮，
双方都能读到结果。

### 6. 常量

面板尺寸、玩家色、动画时长（`kPieceMoveDuration`、`kTutorialStepDuration`）等
全部集中在 `constants/jungle_constants.dart`，widget 内不写魔法值。

## 涉及文件

| 文件 | 改动 |
|---|---|
| `constants/jungle_constants.dart` | 追加 UI 常量 |
| `widgets/jungle_piece_widget.dart` | 加 `flipped` |
| `widgets/jungle_board.dart` | 可空 controller / highlights / AnimatedPositioned |
| `widgets/jungle_player_panel.dart` | **新增** |
| `local/local_game_page.dart` | 重写 |
| `tutorial/tutorial_steps.dart` | **新增** |
| `tutorial/tutorial_page.dart` | **新增** |
| `engine/jungle_engine.dart` | 不动 |

## 验证

`flutter analyze` 无 error（本地无 Java 环境，APK 由 GitHub Actions 流水线构建）。
