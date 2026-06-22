# Dart 移植对照与缺陷规避 · Jungle-Chess

> 仓库：`.claude/repo/Jungle-Chess`（Java）→ 目标：fr 项目（Flutter + Flame + riverpod/provider + hive）
> 主题：逐类移植映射表、源码缺陷清单、落地步骤
> 配套：规则引擎 3 篇 + AI 1 篇（本指南是其"操作手册"）

---

## 1. 逐类移植映射表

| Java 类（行号） | 职责 | Dart 移植建议 |
|---|---|---|
| `Board` (`Board.java:14-258`) | 不可变棋盘状态 | `@immutable class Board`；构造时算合法走法；`Builder`→命名构造 |
| `BoardUtils` (`BoardUtils.java`) | 63 格常量、地形判定、代数记谱、三回重复、终局 | `class BoardUtils`（纯 static）；**解耦 GameFrame**（见 §3） |
| `Terrain` + Empty/Occupied (`Terrain.java`) | 格子（空/占） | 简化为 `class Cell { Piece? piece; }`，地形用 `TerrainType` 枚举 + 坐标查表 |
| `Move` + 4 子类 (`Move.java`) | 走法 | `sealed class Move` + `Standard/Capture/Null/BannedRepetitive` 子类 |
| `MoveTransition` (`MoveTransition.java`) | 走法结果 | data class |
| `MoveStatus` (`MoveStatus.java`) | DONE/INVALID | `enum MoveStatus { done, invalid }` |
| `MoveLog` (`MoveLog.java`) | 走法历史 | `class MoveLog` 封装 `List<Move>` |
| `Piece` (`Piece.java`) | 棋子基类 | `abstract class Piece`；**defenseRank 改 getter**（见 §2） |
| `CommonPiece` / `SpecialPiece` | 标准走法 / 跳河 | `sealed` 子类；跳河抽纯函数 `tryJump(board, from, dir) → (int\|null)` |
| `Rat` / `Elephant` | 特例吃子 | 注意 §2；**勿抄 3 参构造器 bug** |
| `Animal` (`Animal.java`) | 枚举：rank/power/priority | `enum Animal`；rank=枚举 index，power/priority 作字段 |
| `Player` + Blue/Red (`Player.java`,`BluePlayer.java`,`RedPlayer.java`) | 玩家 | 合并为 `class Player(PlayerColor color)`；`isDenPenetrated` 查敌方是否在己穴 |
| `PlayerColor` (`PlayerColor.java`) | 颜色 + 16 张位置表 | `enum PlayerColor`；位置表直接搬 |
| `PlayerType` (`PlayerType.java`) | HUMAN/AI | trivial enum |
| AI：`MoveStrategy`(接口) / `Minimax` / `AlphaBetaWithMoveOrdering` / `PruningOrderingQuiescenceSearch` / `StandardBoardEvaluator` / `MoveSorter` / `BoardEvaluator`(接口) | 搜索 + 评估 | α-β 放 `Isolate`；评估表 `const`；接口→`abstract class` |

---

## 2. 关键重构建议（比原版更干净）

### 2.1 陷阱降级：可变字段 → getter
Java 版用可变 `pieceDefenseRank` + 重建时 `setPiece` 写入（`Board.java:238-242`），有状态漂移风险。Dart 版改成**计算属性**：

```dart
// 建议（无状态，杜绝漂移）
int get defenseRank =>
    BoardUtils.isEnemyTrap(coordinate, color) ? 0 : attackRank;
```
任何时刻查 `defenseRank` 都即时反映当前陷阱状态，无需在重建时维护。

### 2.2 跳河：抽纯函数
把 `SpecialPiece.java:33-72` 的跳河逻辑独立：

```dart
// 建议签名
int? tryJump(Board board, int from, int offset) {
  // offset ∈ {-7, -1, 1, 7}；返回落点坐标或 null（被鼠阻挡/越界）
}
```
单元测试覆盖：纵向跨 3 河格、横向跨 2 河格、被鼠阻挡、落点越界。

### 2.3 走法生成：策略模式
Java 版每种子类各自实现 `determineValidMoves`，重复多。Dart 版可抽 `MoveGenerator` 按动物种类分派，减少重复。

---

## 3. 源码缺陷清单（移植时规避）

| 位置 | 缺陷 | 影响 | 移植对策 |
|---|---|---|---|
| `Board.java:61-69` | `equals()` 残留 7 行 `System.out.println` 调试输出 | AI 搜索每次相等比较都打印，**严重拖慢** | 删除；Dart 版 `==`/`hashCode` 干净实现 |
| `BoardUtils.java:130,142` | `checkThreeFoldRepetition` 直接改 `GameFrame.get()...setValidMoves` | 规则引擎耦合 Swing 单例 | MoveLog/validMoves 作参数传入，零 UI 依赖 |
| `BoardUtils.java:192-199` | 特殊模式胜负引用 `GameFrame.get()`（计时器/认输/回合数） | 模型层依赖 UI 状态 | `isGameOverScenario(board, {blitzTimer, resigned, round})` 显式参数 |
| `Rat.java:24-25` | 3 参构造器误用 `Animal.CAT`（应为 RAT） | 运行不触发（走 2 参），但勿照抄 | 单构造器，字段正确 |
| `Elephant.java:22-24` | 同上，误用 `Animal.CAT` | 同上 | 同上 |
| `Board.java:216-221` | `setBoard()` 未完成解析 + `println` | 死代码 | 忽略 |
| `MoveSorter.java:45-108` | `getIntoEnemyTrapWithoutEnemyNearby` 硬编码所有陷阱坐标 | 不通用 | 改为 `isEnemyTrap` + 邻格遍历 |

---

## 4. 回归测试基准（`database/warnings/*.txt`）

12 个违例测试用例（详见 `Jungle-Chess/GAME_MECHANICS.md` §10），格式：

```
hu hu nu            ← 测试头
<N>                 ← 走法数
bl <from> <to>      ← 走法（bl=蓝/re=红）
...
<下一手方>           ← bl/re
<9 行棋盘>           ← 小写=红, 大写=蓝, **=空, 2字符代码(li/ti/el/le/wo/do/ca/ra)
<mode> <blitz秒>
```

**移植后必须全部通过的规则**（解析 .txt → `Board.constructSpecificBoard()` 还原 → 断言非法走法被拒）：

| Warning | 规则 | 对应实现 |
|---|---|---|
| 3 Move Out of Bound | 越界 | `isInBoundary` |
| 4 Leopard in River | 非鼠/非跳河棋子入河 | `isRiverOrDen` |
| 5 In Your Own Den | 入己方兽穴 | `!isDen(dest, ownColor)` |
| 10 A Player Moves Twice | 连走两次 | 回合交替 |
| 1/7 Missing/Incomplete | 棋子完整性 | 16 子校验 |
| 其余 | 存档格式/回合一致性 | IO 校验 |

> 另有 `database/board_positions.txt`（20 个 AI 测试局面）+ `project info/*.pdf`（2 篇斗兽棋复杂度/残局论文）可作深度参考。

---

## 5. 落地步骤（建议顺序）

1. **纯规则引擎（无 UI）**：`Board`/`Piece`/`Move`/`BoardUtils` 直译为 Dart 不可变类。先实现 `constructSpecificBoard` 解析 .txt。
2. **黄金回归测试**：用 §4 的 12 个 warning 用例做单元测试，非法走法必须被拒。
3. **跳河 + 鼠特例**：抽 `tryJump` 纯函数 + 鼠水陆边界吃子，专项测试覆盖。
4. **AI（Isolate）**：先 BOT2（α-β+MoveOrdering，深度 4-6），评估表 `const` 搬运；后台 isolate + 可取消。
5. **Flame UI**：渲染借鉴 `TochuGV-JungleChess`（`Stack`+`Positioned` + SVG 棋子），见 `_read/TochuGV-JungleChess/UI架构/`。
6. **Demo 注册**：参照 `lib/lab/demos/reversi_demo.dart` 的 `DemoPage` 模式，注册为 `DemoType.game`，挂 lab 游戏中心。

---

## 6. 与 TochuGV 分工

| 维度 | 用 Jungle-Chess（Java） | 用 TochuGV（TS） |
|---|---|---|
| **规则引擎** | ✅ 主参考（完整 + AI + 测试用例） | 辅助对照（纯函数 `getPosibleMoves.ts`，但有规则偏差，见 TochuGV 文档） |
| **AI** | ✅ 唯一来源（3 档 bot） | ❌ 无 AI |
| **UI 渲染** | 仅 Swing 截图参考 | ✅ 主参考（React 组件 → Flutter widget + 24 SVG） |
| **数据模型** | ✅ 完整（Board/Piece/Move/Player） | 辅助（TS 类型更简洁，可借鉴） |

> 移植规则与 AI 看 Jungle-Chess；移植 UI 看 TochuGV。两份 `_read` 文档互补。
