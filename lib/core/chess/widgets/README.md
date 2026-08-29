# Chess 模块 — Widget 占位目录

> 本目录预留给国际象棋 UI 组件，**当前是占位，未包含任何渲染代码**。
> 业务逻辑（`models/`、`engine/`、`p2p/`、`skins/`）已完整，可独立编译运行（17/17 单元测试通过）。

## 一、计划新增的 widget（顺序建议）

| 文件 | 用途 | 依赖 |
|---|---|---|
| `chess_board.dart`     | 8×8 棋盘 + 两色格 + 坐标标签 + 选中 / 走法提示 / 将军 / 升变高亮 | `context.chessColors` + `BoardState` + `List<Move>` |
| `chess_piece.dart`     | 单个棋子的 Image 渲染（按皮肤切换） | `ChessSkin.pieces` + `(PieceType, PieceColor)` |
| `chess_controller.dart`| 触摸 / 拖拽 → Move 转换（与 jungle_chess 的 `JungleTouchController` 同质） | `BoardState` + `ChessEngine` |
| `chess_room_page.dart` | 顶层页面（本地 / 在线对弈入口） | 上述 + `net_p2p_snapshot_chat` 复用 |

## 二、接入原则（与 ui-theme-architecture v6.2.1 对齐）

1. **棋盘颜色统一从 `context.chessColors` 读**：不写 `Color(0xFF...)`
   - `lightSquare` / `darkSquare` / `gridLine` / `coordinateLabel`
   - `selectedSquare` / `lastMoveHighlight` / `legalMoveHint` / `captureHint`
   - `checkWarning` / `checkmateOverlay` / `promotionOverlay` / `promotionBorder`
2. **棋子图案统一从 `ChessSkin.pieces` 读**：由切换器决定
3. **与现有 jungle_chess / reversi 平级**：复用项目 widget 风格（见 `lib/core/jungle_chess/widgets/`）

## 三、测试覆盖（当前）

- ✅ 业务引擎 17/17 单元测试（`test/core/chess/chess_engine_test.dart`）
- ✅ 主题色策略 12/12 单元测试（`test/core/theme/chess_color_strategy_test.dart`）
- 🚧 widget 待接入时再写 golden tests（截图 / 跨主题一致性）

## 四、stub 状态

```
[ ] chess_board.dart
[ ] chess_piece.dart
[ ] chess_controller.dart
[ ] chess_room_page.dart
```

**触发条件**：用户提供 1 套或更多棋子 PNG asset bundle + 棋盘纹理后即可开始。
