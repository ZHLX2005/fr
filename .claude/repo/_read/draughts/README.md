# 国际跳棋 (International Draughts 10×10) 调研

调研日期：2026-10-15 · 目的：为 fr lab 游戏中心新增国际跳棋（联机）

## 结论

**规则权威参考 = `.claude/repo/pydraughts/`**（Python，支持 International/Russian/Brazilian 等 10 变体，
含 flying king + longest-capture 完整规则）。**Flutter 结构参考 = `.claude/repo/draughts-game/`**。
**FEN 格式参考 = `.claude/repo/draughtsboardJS/`**。

## 三份参考分工

| 仓库 | 语言 | 用途 |
|---|---|---|
| `pydraughts/` | Python | **规则权威**。`draughts/core/piece.py`（flying king 吃子几何）、`draughts/core/game.py:485+`（longest-capture 裁决策略）、`draughts/core/board_initializer.py`（编号布局 1-50） |
| `draughts-game/` | Flutter/Dart | **结构参考**。`lib/logic/game_logic.dart`（强制吃子 + 多跳）、`lib/logic/ai_player.dart`（minimax，本项目不做 AI 但结构可看）、`lib/models/`（piece/position/game_state 三件套） |
| `draughtsboardJS/` | JS | **FEN 格式参考**。`draughtsboard.js` 的 FEN 解析；PDN 3.0 规范见 https://wiegerw.github.io/pdn/pdf/pdn_standard.pdf |

## 规则要点（International 10×10）

- 棋盘 10×10，**仅 50 个深色格**可用，编号 1–50（左上起，逐行蛇形）。左下角必须深色。
- 每方 **20 子**，占各自前 4 行；中间 2 行为空。**白方先手**。
- **兵（man）**：斜向**前进** 1 格。**吃子可向前也可向后**（与 English draughts 不同）。
- **王（king）**：斜向**任意距离**移动（flying king），可隔任意距离吃子并自选落点。
- **强制吃子**：有吃子必须吃。
- **最长吃子规则（longest-capture）**：必须选吃子数最多的着法；同长度时用王优先/具体次序见 variant.py。
- **多跳链**：一回合内连吃；**被吃子在整手结束时才移除**；**同一子不可被跳两次**。
- **升王**：走完后停在对方底线即升王；但若该处还能继续（向后）吃，必须继续吃、不升王。
- **胜负**：对方无子或无着可走即胜。**和棋**：同一局面三次重复（不必连续）；王对王自动和。

## 编码约定（本项目采用）

- 内部坐标：`(row, col)`，0-based，10×10。仅 `(row + col) % 2 == 1` 为可用深色格（以左下为深色校准）。
- 方格编号：1–50（对外 / PDN 用）。映射 `square = row * 5 + (col ~/ 2) + 1`（深色格专用）。
- FEN：`<turn>:W<squares>:B<squares>`，如 `W:W31-50:B1-20`（draughts.js / pydraughts 兼容）。
- PDN 着法：`32-28`（走子）/ `32x23`（吃子，含多跳 `32x23x14`）。
