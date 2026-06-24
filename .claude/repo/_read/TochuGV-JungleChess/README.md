# TochuGV-JungleChess 阅读笔记索引

> 仓库：`.claude/repo/TochuGV-JungleChess`（TochuGV，Next.js + React + TypeScript，2025）
> 定位：**斗兽棋移植到 Flutter 的 UI 蓝图**（React 组件 → Flutter widget，24 SVG 可复用）+ 规则逻辑骨架参考
> 仓库根另有 `PROJECT_INDEX.md` 与 `GAME_MECHANICS.md`（20KB 单文综述）。

## 文档导航

### 游戏逻辑（`游戏逻辑/`）
- [01-数据模型与规则TS实现](游戏逻辑/01-数据模型与规则TS实现.md) — `types/game.ts` 模型、`loadBoard` 布局、`getPosibleMoves.ts` 纯函数规则引擎（119 行）、`whoWon`、**5 处规则偏差警示**

### UI 架构（`UI架构/`）
- [01-组件树与Flutter映射](UI架构/01-组件树与Flutter映射.md) — `page.tsx` 编排、绝对定位渲染、SVG 资源、React→Flutter widget 映射表、Stack+Positioned 示例

## 速记

- **棋盘**：7×9，`{x:列0-6, y:行0-8}`，**BLUE 先手**（`turns:[BLUE,RED]`）。
- **规则引擎**：`getPosibleMoves.ts` 纯函数（4 方向 + 狮虎跳河 + 吃子分支），可作 Dart 骨架。
- **规则偏差**（移植须修）：陷阱不区分归属/同色误吃可能、`whoWon` 取 turn-1、无困毙/和棋/AI。
- **UI**：absolute+transform → Flutter `Stack`+`Positioned`；24 SVG（16 棋子+4 地形）零成本复用。
- **无 AI / 无后端棋局**：纯前端双人热座；`api/` 仅用户 CRUD，可忽略。

## 与 Jungle-Chess 分工

| 维度 | TochuGV（本文档） | Jungle-Chess（`_read/Jungle-Chess/`） |
|---|---|---|
| **UI 渲染** | ✅ 主参考 | 仅 Swing 截图 |
| **规则引擎** | 骨架（有偏差需修） | ✅ 完整正确 + AI + 测试 |
| **AI** | ❌ 无 | ✅ 3 档 bot |
| **数据模型** | 辅助（TS 简洁） | ✅ 完整 |

> **移植策略**：规则与 AI 以 Jungle-Chess 为准（完整正确）；UI 以 TochuGV 为蓝图（组件 + SVG）。
