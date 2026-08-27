# 联机围棋（Go）规则引擎调研报告

> 调研日期：2026-08-27
> 目标：为 Flutter 联机围棋（服务端权威 Lua 状态机 + 客户端 Dart 渲染）选 2 个最有价值的开源参考
> 已克隆到 `.claude/repo/` 下

---

## 0. 选型结论（TL;DR）

| 项目 | 语言 | 定位 | 价值点 |
|------|------|------|--------|
| **aprescott/tenuki** | JavaScript | 棋盘规则引擎 + 网页棋盘 UI | 完整实现 **simple ko + 3 种 superko + 自杀判定 + 数子(area)/数目(territory)/等值 3 种记分 + 双活(seki)判定 + Zobrist 局面哈希**。规则引擎与渲染解耦，可直接翻译成 Lua |
| **orca0613/go-game** | Python | 纯规则库（无 UI） | 最简可读：`get_dead_group`（泛洪找群）+ `handle_move`（提子/打劫/自杀）约 70 行。**最适合作为翻译 Lua 的骨架**，自带 3x3~19x19 + 单元测试 |

备选未选：
- `SabakiHQ/go-board`（JS，28★）：Sabaki 的棋盘数据类型，主要是**布局/坐标**而非规则校验，规则较弱。
- `pasky/michi`（Python，277★）：MCTS 引擎，规则是手段不是重点，且被 KataGo 取代。
- `lightvector/GoNN`、`kobanium/TamaGo`：AI 引擎，规则实现纠缠在蒙特卡洛代码里，不适合提取。

**Flutter 生态结论**：Dart 侧**没有**像样的围棋规则引擎包。
- `gobo`（pub.dev）：只是棋盘渲染控件，README 明确写 "Go rules and game logic are **not** included"。
- `justinmc/flutter-go`：教学向拖棋子 demo，无规则。
- 因此服务端 Lua 规则 + Dart 只做渲染的架构是对的，现有 v3 状态机框架直接复用。

---

## 1. 项目详情

### 1.1 aprescott/tenuki（推荐，主要参考）

- GitHub: https://github.com/aprescott/tenuki
- Stars: 131 | Language: JavaScript | License: MIT | 版本 0.3.1
- 定位：网页版围棋棋盘 + **与渲染解耦的 JS 规则引擎**（`Game`/`BoardState`/`Ruleset`/`Scorer`/`Region`）。规则引擎可在 Node 环境独立跑，测试完备。
- 已 clone 到 `.claude/repo/tenuki/`，核心文件：
  - `src/board-state.js` — 落子 + 提子 + ko point 计算 + 群/气（`groupAt`/`libertiesAt`/`inAtari`）
  - `src/ruleset.js` — 非法手判定：占位、**自杀**、**simple ko / positional-superko / situational-superko / natural-situational-superko**
  - `src/scorer.js` — 数子(area) / 数目(territory) / 等值(equivalence)，含双活(seki)修正与假眼填充
  - `src/region.js` + `src/eye-point.js` — 空区划分、眼数判定（真眼/假眼）
  - `src/zobrist.js` — 局面 Zobrist 哈希（superko 查重用）

### 1.2 orca0613/go-game（推荐，翻译骨架）

- GitHub: https://github.com/orca0613/go-game
- Stars: 0 | Language: Python | License: 无明确 LICENSE（README 是模板，个人项目）
- 定位：纯规则库，无 UI、无依赖。README 声明支持 3x3~19x19、提子/打劫/自杀、单元测试。
- 已 clone 到 `.claude/repo/go-game/`，核心文件：
  - `my_package/go_logic.py` — 全部核心：`get_neighbors` / `get_dead_group`（泛洪找群）/ `remove_stones` / `handle_move`（提子+自杀+ko_spot 检测）
  - `my_package/go_game.py` — 状态机包装：落子合法性（ko spot 禁止）、走子历史（`record`，支持复盘跳转）、执子切换
  - `my_package/constants.py` — `min_size=3, max_size=19, EMPTY=".", BLACK="b", WHITE="w"`

---

## 2. 核心规则算法伪代码（可直接翻译 Lua）

### 2.1 提子判定（capture）

通用要点：气(liberty) = 与该棋群 4 相邻的空点集合大小。落子后，先提对方无气群，再检查自身是否自杀。

**方案 A：orca0613 泛洪标记法**（简单直接，推荐 Lua 用）
```
function get_dead_group(board, coord, color):
    # 返回以 coord 为起点的、属于 color 的"无气群"；有气则返回空
    if 越界(coord) or board[coord] != color: return []
    opponent = 对方(color)
    new_board = 深拷贝(board)
    dead = []; stack = [coord]
    while stack 非空:
        cur = stack.pop()
        if 越界(cur): continue
        if new_board[cur] == color:
            new_board[cur] = opponent        # 标记为已访问
            dead.append(cur)
            stack += get_neighbors(cur)      # 上下左右
        elif new_board[cur] == opponent:
            continue                          # 已访问或对方棋子
        else:  # 遇到空点 -> 说明有气
            return []                         # 群有气，不死
    return dead

function handle_move(board, move, color):
    new_board = 深拷贝(board); new_board[move] = color
    killed = []
    for n in get_neighbors(move):
        killed += get_dead_group(new_board, n, opponent)
    suicide = get_dead_group(new_board, move, color)
    if killed 为空 and suicide 非空: return board  # 自杀，禁止
    if killed.size == 1 and suicide.size == 1:
        ko_spot = killed[0]                    # 单子打劫候选
    for k in killed: new_board[k] = EMPTY
    return new_board, ko_spot
```
注意：`get_dead_group` 里"把访问过的同色改成对方色"是关键技巧——避免重复入栈，且遇到空点即可短路判定有气，一个函数同时服务"提子扫描"与"自杀判定"。

**方案 B：tenuki 气计数法**（结构化，语义更清晰）
```
function libertiesAt(y, x):
    group = groupAt(y, x)                     # 同色连通块（partitionTraverse）
    empty_set = {}
    for p in group:
        for n in neighbors(p):
            if n 为空: empty_set.add(n)
    return empty_set.size                       # 唯一空点计数

function _capturesFrom(y, x, color):
    captured = []
    for n in neighbors(y, x):
        if n 非空 and n.value != color and libertiesAt(n) == 1:
            captured += groupAt(n)              # 对方"打吃"中，整群提掉
    return unique(captured)

function playAt(y, x, color):
    captured = _capturesFrom(y, x, color)
    new_board = 先移除所有 captured 位置，再落子
    return new_state(capturedPositions=captured, ...)
```
结论：**提子用"落子后移除无气对方群"（方案 A）更贴近标准规则；`libertiesAt==1`（方案 B）更适合做"打吃/叫吃 in-atari"提示**（客户端 UI 有用）。

### 2.2 打劫判定（ko / superko）

围棋有 4 档劫规，从易到难：

**简单劫（simple ko）** — 多数联机游戏默认，orca0613 与 tenuki 默认都用它：
```
# 每次落子后更新 ko_spot：
if killed.size == 1 and suicide.size == 1:
    ko_spot = killed[0]          # 单子被提、单子落成（打劫形状）
else:
    ko_spot = null

# 落子前校验：
if move == ko_spot: 拒绝        # 禁止立即回提
```
tenuki 更精确的判定（`_simpleKoPoint`）：只有"本次落点形成的群是单子 **且** 被提点唯一 **且** 新子处于 atari（只有 1 气）"才标记 ko point。

**超级劫（superko）** — 禁止任何局面重复（tenuki 支持 3 种）：
```
positional-superko：              # 只比局面哈希，不管轮到谁
    新局 hash 在历史中出现过 → 非法
situational-superko：             # 局面 + 轮到谁
    新局 hash 且 nextColor 相同 → 非法
natural-situational-superko：     # 排除 pass 产生的情况
    state.color == newState.color 且 非 pass → 非法
```
实现依赖**局面哈希**：tenuki 用 Zobrist（`src/zobrist.js`，对每个 (size,y,x,value) 生成随机 31bit 值，整个局面 XOR）。**Lua 翻译时注意：Zobrist 随机数表要固定种子**，否则服务器重启后同一局面哈希不稳定；更稳妥的做法是直接存字符串局面快照或用确定性哈希（如对每个落子点编码后 hash）。

### 2.3 自杀判定（suicide）

中国规则：不允许自杀（落下即提自己、且不提对方 → 非法）。两套实现都覆盖：

**方案 A（orca0613）**：落子后 `get_dead_group(new_board, move, color)` 非空 **且** killed 为空 → 自杀，返回原盘。

**方案 B（tenuki，纯预判不落子）**：
```
function _wouldBeSuicide(y, x, state):
    # 1) 该点是空点，且 4 邻无空点（已被包围）
    if not (该点为空 and 邻点全非空): return false
    # 2) 若任一己方邻居不在 atari（气>1），落子后能接气 → 非自杀
    if 存在己方邻居 且 不在atari: return false
    # 3) 若任一对方邻居在 atari（气==1），落子即提子 → 非自杀
    if 存在对方邻居 且 在atari: return false
    return true
```
方案 B 不改变棋盘状态即可判定，适合作为**客户端预校验/合法手提示**；服务端权威仍建议用方案 A 的"试落 + 判定"更不易漏边界。

### 2.4 真眼 / 活棋 / 数子（记分，可选）

**真眼 vs 假眼（tenuki `eye-point.js`）**：
```
function isFalse(eye):
    if 该点非空: return false
    diagonals = 对角 2~4 个点
    occupiedNeighbors = 非空邻居
    onFirstLine = diagonals.size <= 2          # 一线/角上
    if onFirstLine and occupiedNeighbors.size < 1: return false
    if not onFirstLine and occupiedNeighbors.size < 2: return false
    opposing = diagonals 中 非空 且 颜色与己方不同 的点
    return onFirstLine ? opposing.size >= 1 : opposing.size >= 2
```

**记分两套（tenuki `scorer.js`）**：
- **数子（area，中国规则）**：黑分 = 黑存活子数 + 黑空数；白分 = 白存活子数 + 白空数。`territory()` 先移除死子点，再对每个空区检查边界颜色是否唯一。
- **数目（territory，日本规则）**：黑分 = 黑空数 + 提子数 + 白死子数。需要双活(seki)修正：`Region` 的空区 `numberOfEyes()` 按边界周长估算眼数，合并空区后总眼数 < 2 视为双活不计目（`TerritoryScoring` 里 `eyeCounts.reduce >= 2`）。
- 中国规则下**不需要双活修正**（双活双方各占交叉点，直接数子即可）——**联机游戏建议直接上中国数子规则**，逻辑最省：不需要"提子数记账"、不需要 seki 判定，只需要死子标记（服务端可做"双方确认死子"或简单两连 pass 结束）。

**pass 结束**（tenuki `game.js`）：连续两次 pass（双方各一次）→ `isOver()`。服务器权威应在此基础上加"pass 计数/协商"。

---

## 3. 哪些放服务端权威 Lua、哪些放客户端

| 逻辑 | 位置 | 理由 |
|------|------|------|
| 落子合法性（占位/越界） | 服务端权威 + 客户端预校验 | 客户端即时反馈；服务端兜底 |
| 提子（无气群移除） | **服务端权威** | 状态机核心，必须单真源 |
| 打劫（simple ko） | **服务端权威** | 依赖完整历史/上一步状态 |
| superko（若启用） | **服务端权威** | 需要历史局面哈希表，客户端不必持有 |
| 自杀判定 | 服务端权威；客户端可预判提示 | tenuki 的 `_wouldBeSuicide` 可作客户端参考 |
| 打吃（atari）高亮 | **客户端** | 纯展示，`libertiesAt==1` 本地算 |
| 合法落点高亮 | 客户端 | 本地算一次即可，省网络往返 |
| 真眼/活棋/死子标记 | 服务端权威判定 + 客户端展示 | 记分需权威；展示层只画 |
| 终局记分（数子/数目） | **服务端权威** | 中国数子最省，建议默认 |
| 落子历史/复盘跳转 | 服务端存记录（可广播），客户端缓存 | orca0613 的 `record` 模式可借鉴 |

**对现有 v3 状态机的移植建议**：
- v3 已有"服务端权威 + 广播"骨架，围棋只需要新增一个 `go_logic.lua`（翻译 orca0613 的 `go_logic.py`，约 70 行核心）+ 一个 `go_state.lua`（ko_spot + 提子计数 + 历史）。
- 消息协议只需"落子(x,y)"与"pass"，其余（atari、合法点高亮）全部客户端本地算。
- 若后续要 5x5 小棋盘，`constants.py` 的 `min_size=3` 已说明围棋规则天然支持任意 N x N（3~19），5x5 不需要任何规则改动。

---

## 4. 5x5 小棋盘先例

**结论：5x5 围棋本身有先例（已求解），但没有专门的"5x5 变体"开源规则库——因为规则完全复用标准围棋，无需变体实现。**

证据：
1. **5x5 围棋已被完全求解**（Strongly solved，黑先必胜）：维基百科 Go 条目引用 Tromp 的 "Counting Legal Positions in Go"（2016）确认 "5x5 Go is solved"。存在免费求解程序（可在网上找到，非标准开源 repo）。
2. **现有引擎天然支持任意尺寸**：
   - orca0613/go-game：`min_size=3, max_size=19`，构造 `Go_game(5)` 即得 5x5。
   - tenuki：`boardSize` 参数化，README 示例即有 9x9/13x13/19x19（多棋盘示例）；19 是硬上限，5 完全支持。
3. **5x5 下的规则特殊性**（值得注意）：
   - 棋盘过小，**双活(seki) 几乎不出现**（空间不够形成"各自无气但互不能提"的循环），中国数子规则下记分更简单。
   - 打劫在小棋盘上更常见且影响更大（局部劫争夺可能决定整盘），**simple ko 必须正确实现**。
   - 有"五五围棋"民间叫法，但本质就是标准围棋规则 + 5x5 棋盘，无额外变体规则。

---

## 5. 可执行下一步

1. **翻译骨架**：照 orca0613 `go_logic.py` 写 `go_logic.lua`（约 70 行），包含 `get_dead_group` / `handle_move` / `remove_stones`；单元测试直接搬 `test.py` 的 3x3 用例（自杀/提子/打劫各 1 个）。
2. **状态机接入**：`Go_game` 类（record 历史 + ko_spot + 执子）对应 v3 的 state machine 层。
3. **记分**：默认中国数子（area）+ 死子标记 + 双 pass 结束，跳过日本数目的 seki 复杂度；tenuki 的 `Region.allFor` + `isTerritory` 逻辑（约 30 行）足够翻译。
4. **客户端**：Dart 只画棋盘/棋子 + 本地算 atari 与合法点提示，不重复实现提子/打劫。
5. **superko**：先只做 simple ko；若对局可长，再加"历史局面 Zobrist 哈希 + positional-superko"（注意 Lua 里随机表固定种子或改确定性哈希）。

---

## 附：搜索过程记录

- `WebSearch` 工具 API 报错不可用；`mcp__MiniMax__web_search` API key 失效；最终使用 `mcp__web-search-prime` 完成。
- 候选池（按相关度）：tenuki(JS) / orca0613/go-game(Python) / SabakiHQ/go-board(JS) / pasky/michi(Python) / lightvector/GoNN / kobanium/TamaGo / xuhui/Go-1(Java 规则) / CGLemon/Sayuri(围棋引擎) / justinmc/flutter-go / gobo(pub.dev)。
- Flutter/Dart 侧确认无规则引擎（gobo 明确不含规则），故选择语言无关的 JS + Python 规则引擎。
