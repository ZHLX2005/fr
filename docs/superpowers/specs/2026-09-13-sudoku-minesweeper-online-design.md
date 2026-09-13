# 数独竞赛 / 扫雷竞赛 联机设计

**日期**：2026-09-13
**作者**：Claude
**状态**：Draft，待 plan

## 1. 目标与边界

为 `lib/lab` 已有的数独、扫雷 demo 补齐联机对弈能力，落地到现有 `lib/core/<game>/` 框架下，复用 chess/tetris 走通的 smartMatch + relay v3 + Lua 状态机模式。

**不在范围内**：
- 不引入 Firebase、不接外部对战服务
- 不重写 `relay_v3` 协议本身
- 不动 chess/tetris 已落地代码（仅借鉴结构，不强行复用内部组件）
- 不做残局库 / 排行榜 / 复盘（首版聚焦能跑通）

## 2. 模块结构

镜像 `lib/core/chess/` 结构：

```
lib/core/sudoku/
├── sudoku.dart                       # 入口
├── lobby/sudoku_lobby_spec.dart      # GameLobbySpec const
├── models/
│   ├── sudoku_puzzle.dart            # {puzzle: int[81], solution: int[81], difficulty, seed}
│   ├── sudoku_board.dart             # 9×9 二维 cells
│   └── sudoku_cell.dart              # value/isInitial/notes/isError
├── engine/
│   ├── sudoku_generator.dart         # 对称交换挖洞（保证唯一解）
│   └── sudoku_validator.dart         # 行/列/宫冲突检测
├── widgets/{sudoku_grid,sudoku_cell,number_pad,error_badge,opponent_strip}.dart
└── p2p/                              # ★ 参考 chess/p2p/ 拆分
    ├── sudoku_room_page.dart         # lobby/ready/playing/ended 主循环
    ├── sudoku_room_config_page.dart  # 准备阶段：难度选 + 生成 puzzle（host only）
    ├── sudoku_net.dart               # 动作编码 + 快照解码
    └── script/
        ├── sudoku_script.dart        # 入口 + assembler 拼接
        ├── sudoku_script_lifecycle.dart  # on_init/on_join/on_leave
        └── sudoku_script_actions.dart    # SET_PUZZLE / START / SUBMIT

lib/core/minesweeper/                  # 同结构
├── minesweeper.dart
├── lobby/minesweeper_lobby_spec.dart
├── models/{minesweeper_board,minesweeper_seed}.dart
├── engine/{board_generator,flood_fill,reveal}.dart
├── widgets/{minesweeper_grid,cell_widget,score_bar,opponent_strip}.dart
└── p2p/
    ├── minesweeper_room_page.dart
    ├── minesweeper_room_config_page.dart   # 准备阶段：规格选 + seed
    ├── minesweeper_net.dart
    └── script/{minesweeper_script,_lifecycle,_actions}.dart

lib/lab/demos/sudoku_lua/
├── sudoku_demo.dart                  # 暴露 demo 入口（含 router）
├── sudoku_script.dart                # 兼容入口（迁入 lib/core/sudoku 后删除或转 re-export）
└── constants.dart

lib/lab/demos/minesweeper_lua/         # 同结构
```

**主题色通道**：新增
- `lib/core/theme/colors/strategy/sudoku_color_strategy/sudoku_color_strategy.dart`
- `lib/core/theme/colors/strategy/minesweeper_color_strategy/minesweeper_color_strategy.dart`
- `lib/core/theme/tokens/color/sudoku/*.dart`
- `lib/core/theme/tokens/color/minesweeper/*.dart`

参考 `ui-theme-architecture` skill 五主题（zen / purple / ink / rose / lemon）规范。

## 3. 联机协议

### 3.1 入口

smartMatch 单按钮（与 tetris 一致）：
- 主按钮「进入对局」 → `tryJoinOrCreate`
- 先到者 = host（房主）
- 后到者 = guest
- maxPlayers = 2
- 自动开始规则：host 进入 lobby 后展示准备卡，guest 加入后 host 配规则 → START

### 3.2 数独 Lua 状态机（kSudokuScript）

```lua
state = 'lobby'
players = {}            -- {[uid]=true}
host_id = nil
guest_id = nil
difficulty = nil        -- 'easy'|'medium'|'hard'
puzzle = nil            -- int[81]，0 = 空，1-9 = 初始填入
solution = nil          -- int[81]，1-9（host 上传，服务端校验唯一解后存）
seed = nil              -- 题目生成种子（用于客户端复现）
started_at_ms = nil     -- state='playing' 的服务端时间戳
finished_at_ms = {}     -- {[uid]=ms}
error_count = {}        -- {[uid]=int}
winner_id = nil
```

**actions**：
- `SET_PUZZLE`（host only）：`{puzzle, solution, seed, difficulty}`
  - 服务端校验：① solution 长度=81 且值 ∈ [1,9]；② puzzle 与 solution 兼容（puzzle 非 0 格 == solution 对应格）；③ solution 自身合法（行/列/宫）；④ puzzle 解唯一（用 solution 做一次填入试探是否有第二解，简单做法：要求服务端调用 validator 走唯一性检查，超时则拒绝）
  - 校验通过：写入 `puzzle / solution / seed / difficulty`，广播（host/guest 可见）
- `START`（host only）：`state='playing'`，记录 `started_at_ms`，广播（带 puzzle）
- `SUBMIT`（player）：`{values: int[81], elapsed_ms, errors: int}`
  - 服务端校验：`values === solution` → 写 `finished_at_ms[uid] = elapsed_ms`、`error_count[uid] = errors`
  - 若 `winner_id == nil`：`winner_id = uid`、`state='ended'`，广播
  - 否则仅记录（晚到完成也算分）
- `LEAVE`：常规

### 3.3 扫雷 Lua 状态机（kMinesweeperScript）

```lua
state = 'lobby'
players = {}
host_id = nil
guest_id = nil
spec = nil              -- {rows, cols, mines}
seed = nil              -- int，服务端定
started_at_ms = nil
finished_at_ms = {}
hit_mine = {}          -- {[uid]=bool}
completed = {}          -- {[uid]=bool}
winner_id = nil
```

**actions**：
- `SET_SEED`（host only）：`{seed, rows, cols, mines}` → 服务端校验 spec 合法性（rows×cols > mines，rows/cols ∈ [4, 30]，mines ∈ [1, rows*cols/2]）→ 存
- `START`（host only）：`state='playing'`，`started_at_ms=now`，广播（带 seed + spec）
- `HIT_MINE`（player）：`{hit=true}` → `hit_mine[uid]=true`，该玩家本局结束（不广播 click 流；只在终局时上报结果）
- `SUBMIT`（player）：`{elapsed_ms, cells_revealed: int, completed: bool}`
  - 服务端用 seed 重渲染 board，按 spec 校验 `completed`（cells_revealed == rows*cols - mines）或 `hit_mine[uid]==true`
  - 若 `completed == true` 且 `winner_id == nil` → `winner_id = uid`、`state='ended'`，广播
  - 否则等另一玩家结束

### 3.4 反作弊要点

- **数独**：服务端持有 solution，SUBMIT 时服务端比对，杜绝客户端伪造时间/答案。
- **扫雷**：服务端持有 seed，SUBMIT 时服务端用同 seed 重渲染并按 spec 验证 completed 标志。
- **Lua 校验必须轻量**：唯一解校验若太重可降级为「host 上传 solution 时同时上传一个唯一性证明（候选填空法的回溯计数）」，但首版先走服务端简单回溯（10ms 内可接受）。

## 4. 准备阶段（参考 chess）

参考 `lib/core/chess/p2p/chess_room_config_page.dart` 的 `ChessRoomRulesPanel` —— 一个**可嵌入的 StatefulWidget**，挂在 lobby/ready 卡内（不是 push 全屏新页面）。

### 4.1 数独准备卡（`SudokuRoomConfigPanel`）

```
┌────────────────────────────┐
│ 难度选择                    │
│ ◯ Easy  (35 filled)        │
│ ◉ Medium (30 filled)       │
│ ◯ Hard  (25 filled)        │
│                            │
│ [host 视图] 生成题目中…     │
│    完成：题已生成 ✓         │
│    「重新生成」按钮         │
│                            │
│ [guest 视图] 等待 host 选题 │
└────────────────────────────┘
```

行为：
- host 选难度 → 触发 `SudokuGenerator.generate(difficulty)` → 调 `SET_PUZZLE` 上传
- guest 视图只读，展示当前难度 + 「题已生成」状态
- 双方都「准备」后 host 看到「开始对局」按钮（参考 chess 的 ready gate）

### 4.2 扫雷准备卡（`MinesweeperRoomConfigPanel`）

```
┌────────────────────────────┐
│ 规格选择                    │
│ ◯ 9×9 ×10 雷（入门）        │
│ ◉ 9×9 ×15 雷（标准）        │
│ ◯ 16×16 ×40 雷（高级）      │
│ ◯ 自定义…                   │
│                            │
│ [host 视图] 「生成棋盘」    │
│    完成：seed=… ✓           │
│                            │
│ [guest 视图] 等待 host 设置 │
└────────────────────────────┘
```

行为：同数独，但 spec 用预置三档（不开放自定义 UI，首版减少组合爆炸；自定义留 TODO）。

## 5. 房间页状态机

参考 `ChessRoomPage` 的 lobby → ready → playing → ended 切换：

| state | 触发 | 展示 |
|---|---|---|
| `lobby` | host createRoom | 准备卡 + 房间号 + 「等待对手加入」 |
| `ready` | guest joinRoom | 准备卡 + 双方昵称 + 「等待 host 开始」/「开始对局」 |
| `playing` | host START | 顶部双玩家条（昵称 + 计时 + 完成度）+ 棋盘 + 数字键盘/操作条 |
| `ended` | 任一 SUBMIT 触发 winner | 结束页：赢家 + 用时 + 错误数 + 「再来一局」/「返回大厅」 |

**房间页组件**（数独 / 扫雷各自实现）：
- `XxxRoomPage` —— `RoomHandle` 入口，订阅 snapshot，按 state 分发子组件
- `XxxLobbyPanel` —— lobby/ready 状态显示
- `XxxReadyPanel` —— 嵌入 `XxxRoomConfigPanel`（host editable / guest 只读）
- `XxxPlayingPanel` —— 主棋盘 + 计时 + 错误数
- `XxxEndedPanel` —— 结果 + 操作按钮

**Opponent Strip**（参考 chess 的 player_strip.dart）：双方昵称 + 计时 + 完成度（如「已填 23/81」「已揭 47/81」），位于棋盘上方。

## 6. UI 主题适配

- 棋盘主色走 `context.colors` 通道，不写死 `Color(0xFF...)`
- 新增 `SudokuColorStrategy` / `MinesweeperColorStrategy`，提供：cell-bg / cell-text / cell-selected / cell-error / cell-initial / cell-note / grid-line / accent
- 五主题（zen / purple / ink / rose / lemon）下都需有合理配色（参考 chess/tetris strategy 文件中的默认实现）
- 错误格 / 完成度反馈用 token，不在 Widget 内计算颜色

## 7. 测试策略

- **单元**：
  - `sudoku_generator_test`：生成难度 → 解唯一 → 行/列/宫合法
  - `sudoku_validator_test`：合法/非法 board、note 增删
  - `minesweeper_board_generator_test`：固定 seed → board 布局一致 + 雷数正确
  - `minesweeper_flood_fill_test`：边界展开正确
  - `minesweeper_reveal_test`：触雷结束
- **集成**（Lua 脚本级）：
  - `sudoku_script_guard_test`：参考 `test/core/chess/p2p/chess_script_guard_test.dart` 风格——校验导出表、helper 顺序
  - `minesweeper_script_guard_test`：同上
  - `sudoku_ready_gate_test`：参考 chess 的 ready gate 测试——guest 加入前 host 不能 START
- **手动**：参照 chess/tetris 的 `/qa` 流程跑端到端

## 8. 风险与权衡

| 风险 | 缓解 |
|---|---|
| 服务端 Lua 不支持复杂数独生成 | host 端生成 puzzle + 上传 solution；服务端只校验不解题 |
| 服务端反作弊 Lua 写复杂校验易出 bug | 校验逻辑保持最小（长度+值域+解唯一）；复杂校验降级为「信任 host」+ 后续加审计 |
| relay v3 transport 复用 chess 的实例但 chess 是连续动作、数独是离散回合 | 不复用 chess_net；新建 `sudoku_net.dart` / `minesweeper_net.dart` |
| 主题色策略新增两个文件可能漏主题 | 写完先走 `lib/lab` 现有主题切换器全 5 主题过一遍，记录漏掉 |
| minesweeper 同 seed 双端渲染要保证确定性 | `board_generator` 用纯 Dart `Random(seed)`，不依赖 `DateTime.now()` 或系统熵 |

## 9. 实施分解

拆 3 个相对独立的阶段（每个阶段自己一份 plan）：

1. **stage-1 数独联机**：sudoku_lobby_spec + 数独生成器/validator + Lua script + RoomPage + ConfigPanel + 主题
2. **stage-2 扫雷联机**：minesweeper_lobby_spec + 板生成/flood_fill + Lua script + RoomPage + ConfigPanel + 主题
3. **stage-3 demo 入口与 QA**：lab 下 demo 页注册、路由接通、`/qa` 端到端跑通

每阶段独立 shippable + 可回滚。
