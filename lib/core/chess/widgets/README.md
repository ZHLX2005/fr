# Chess 模块 — Widget UI 层

本目录实现国际象棋 UI widget 层（依赖 `lib/widgets/context_chess_colors.dart`
提供的 `context.chessColors`，以及 `lib/core/chess/` 下的业务 / 皮肤契约）。

## 一、文件清单

| 文件 | 用途 | 依赖 |
|---|---|---|
| `chess_piece.dart`      | 单个棋子的 Image 渲染（PNG / WebP 透明图） | `ImageProvider` + `size` |
| `chess_board.dart`      | 8×8 棋盘 + 两色格 + 坐标 + 选中/上一步/合法走法/吃子高亮 | `context.chessColors` + `BoardState` + `ChessSkin` |
| `chess_controller.dart` | 触摸状态机（选中 / 切换 / 走法生成 / 应用 + emit / 升变暂停） | `ChessEngine` + `BoardState` + `Move` |
| `promotion_panel.dart`  | 升变选择面板（Q/R/B/N 悬浮层，点击遮罩取消） | `context.chessColors` + `ChessSkin` + `PieceType` |
| `chess_room_page.dart`  | **P2P 在线对弈房间页**（快照驱动 / kChessScript / 乐观走子 + 服务端调和） | `RoomHandle` + `ChessBoard` + `ChessEngine` + `PromotionPanel` |
| `README.md`             | 本文件 | — |

> **未实现（v2 计划）**：将军警告覆盖层、走法历史、动画、声音。

## 二、接入原则（与 ui-theme-architecture v6.2.1 对齐）

1. **棋盘颜色统一从 `context.chessColors` 读**（不写 `Color(0xFF...)`）：
   - `lightSquare` / `darkSquare` / `gridLine` / `coordinateLabel`
   - `selectedSquare` / `lastMoveHighlight` / `legalMoveHint` / `captureHint`
2. **棋子图像统一从 `ChessSkin.pieces` 读**：UI 不写 `AssetImage(...)`
3. **业务走 `ChessEngine` / `BoardState` / `Move`**，不在 widget 内做走法生成
4. **皮肤注册**：`main.dart` 启动期调 `ChessSkinBundle.registerHardcoded()`

## 三、tap 流程（`ChessController`）

```
ChessController
  ├── GestureDetector（来自 ChessBoard 内部 64 cell）
  └── ChessBoard
        ├── 棋盘底图（如果 skin.boardBackground 非空）
        ├── 64 格两色 / 坐标 / 走法提示圆点（HitTestBehavior.opaque）
        └── 32 棋子 Positioned（IgnorePointer，不抢 tap）
```

`ChessController._handleTap` 状态机：

| 当前状态 | 点击位置 | 动作 |
|---|---|---|
| 无选 | 己方棋子 | 选中 |
| 无选 | 对方 / 空 | no-op |
| 已选 A | A 同格 | 清选 |
| 已选 A | 己方棋子 B | 切换到 B |
| 已选 A | A 合法目标（非升变） | 应用走法 + emit + 清选 |
| 已选 A | A 合法目标（升变） | 弹 `PromotionPanel`，等玩家选 Q/R/B/N 再应用 + emit |
| 已选 | 其它 | 清选 |

> 升变：兵到底线时暂停走法应用，弹出 `PromotionPanel`（半透明遮罩 + 4 个
> Q/R/B/N 棋子按钮）。选完才应用走法 + emit；点遮罩取消（回到未选状态）。

## 四、测试覆盖

| 测试文件 | 数量 | 覆盖 |
|---|---|---|
| `chess_piece_widget_test.dart`  | 1 | MemoryImage → ChessPiece → Image 渲染（width / height / fit） |
| `chess_board_widget_test.dart`  | 5 | 默认皮肤 unicode fallback / 32 个 ChessPiece / tap 1D index / 高亮参数 / 黑方翻转 |
| `chess_controller_widget_test.dart` | 4 | 选中 / 应用走法 / 对方 no-op / 非法目标清选 |
| `promotion_panel_test.dart`   | 4 | e7 兵到底线弹面板 / 选 Q 升后 / 选 R 升车 / 点遮罩取消 |
| `chess_room_page_test.dart`   | 6 | P2P 房间页：初始渲染 / 走子发 MOVE / 非我回合 no-op / 快照更新 / 将杀覆盖层 / RESIGN |

合计 widget 测试 20 个；chess 模块总测试数 82。

## 五、stub 状态

```
[x] chess_piece.dart
[x] chess_board.dart
[x] chess_controller.dart
[x] promotion_panel.dart
[x] chess_room_page.dart     ← P2P 在线对弈房间页（快照驱动）
[ ] move history / undo      ← v2
```

**触发 v2 的条件**：用户接入 P2P 在线对弈（`ChessRoomPage` 已就绪，缺入口路由）+ 动画需求时。

## 六、P2P 在线入口

Lab 演示入口：`lib/lab/demos/chess_online_demo.dart`（`ChessOnlineDemo`，slug `chess-online`）。
流程：`RelayV3Lobby`（v3 Lua 状态机大厅，host=白 / guest=黑）→ 房主开始 → `onStarted(RoomHandle)`
→ `Navigator.push` 到 `ChessRoomPage(handle:)`。已登记 Lab bootstrap + 游戏中心 `kGameMeta`。
