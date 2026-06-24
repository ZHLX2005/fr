# Jungle-Chess 阅读笔记索引

> 仓库：`.claude/repo/Jungle-Chess`（Layheng-Hok/Jungle-Chess，Java + Swing，SUSTech CS109，110/100）
> 定位：**斗兽棋移植到 Flutter/Flame 的规则引擎底座**（完整规则 + 3 档 AI + 12 个违例回归用例 + 2 篇研究论文）
> 仓库根另有 `PROJECT_INDEX.md`（结构索引）与 `GAME_MECHANICS.md`（27KB 单文综述，本目录是其主题化拆分）。

## 文档导航

### 规则引擎（`规则引擎/`）
- [01-棋盘模型与地形](规则引擎/01-棋盘模型与地形.md) — 9×7 一维坐标、代数记谱、初始布局表、河流/陷阱/兽穴坐标、Builder 陷阱降级入口
- [02-棋子体系与吃子规则](规则引擎/02-棋子体系与吃子规则.md) — Animal 枚举（rank/power/priority）、Piece 模型、4 类棋子、吃子四特例（鼠克象/陷阱降0/水陆边界/象不克鼠）
- [03-走法生成与走子执行](规则引擎/03-走法生成与走子执行.md) — Move 层级、MoveFactory、不可变 execute、跳河算法、三回重复、终局判定

### AI 引擎（`AI引擎/`）
- [01-评估函数与三档搜索](AI引擎/01-评估函数与三档搜索.md) — 4 分量评估 + 16 张位置表、Minimax/α-β+MoveOrdering/+Quiescence、MoveSorter

### 移植指南（`移植指南/`）
- [01-Dart移植对照与缺陷规避](移植指南/01-Dart移植对照与缺陷规避.md) — 逐类映射表、重构建议、源码缺陷清单、回归测试、落地步骤、与 TochuGV 分工

## 速记

- **棋盘**：63 格，`index=row*7+col`，行0=红(顶)/行8=蓝(底)，**蓝先手**。
- **吃子**：`attackRank ≥ defenseRank`；陷阱中 defenseRank=0；鼠克象/象不克鼠/鼠出水不吃岸。
- **胜负**：入对方兽穴 / 吃光 / 困毙 / 超时 / 认输 / 150 回合和棋。
- **AI**：α-β+MoveOrdering(深度6) 性价比最高，放 Isolate。
- **缺陷**：`Board.equals` 残留 println、终局耦合 GameFrame、Rat/Elephant 构造器误用 CAT——移植全规避。

## 配套
- UI 蓝图见 `_read/TochuGV-JungleChess/`（React 组件 → Flutter widget + 24 SVG 棋子可直接复用）。
- fr 项目接入点：`lib/lab/demos/reversi_demo.dart`（同类 `DemoPage` 注册模式）。
