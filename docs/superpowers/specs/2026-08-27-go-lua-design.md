# 联机围棋（Go · Lua 服务端权威）设计文档

> 日期：2026-08-27
> 状态：设计定稿，待实现
> 参考：现有 `gomoku_lua`（v3 联机模式）；规则翻译自 `orca0613/go-game`（75 行 Python，MIT）+ `aprescott/tenuki`（JS，MIT）+ `golo`（Dart，MIT）

---

## 1. 目标与一句话

仿照现有 `gomoku_lua`（五子棋联机）完整架构，新增 `go_lua` 模块：
**服务端 Lua 权威计算落子（提子/打劫/自杀/过手/数子），客户端 Dart 纯渲染 + 落子音效 + atari 提示**，接入游戏中心「联机 · 棋游」。

## 2. 核心架构决策

### 决策 1 — 服务端权威规则计算

围棋落子**依赖当前棋盘状态**（提子会移除棋子）。若像五子棋那样只存 history、客户端重放，会：
- 客户端可发非法 MOVE（占位/自杀/打劫回提）作弊
- 提子结果双方时序不一致

所以：**服务端 Lua 每次 MOVE 从 history 重放棋盘 → 校验（占位/自杀/打劫）→ 提子 → 记 ko_spot → 更新捕获数 → 追加 history。客户端纯渲染，零规则计算。**

这与 reversi（黑白棋）"服务端权威计算落子结果"同模式，但围棋规则更完整。

### 决策 2 — 规则翻译自 orca0613/go-game（75 行 Python，最简骨架）

```lua
-- get_dead_group: 泛洪找无气群；有气返回空
function get_dead_group(board, coord, color)
  if is_outside(coord, size) or board[y][x] ~= color then return {} end
  local opponent = (color == 1) and 2 or 1
  local nb = deepcopy(board)   -- 局部新盘，避免污染
  local dead = {}; local stack = {coord}
  while #stack > 0 do
    local cur = table.remove(stack)
    if not is_outside(cur) then
      local cy, cx = cur[1], cur[2]
      if nb[cy][cx] == color then
        nb[cy][cx] = opponent    -- 标记已访问
        table.insert(dead, cur)
        -- push 四邻
      elseif nb[cy][cx] == opponent then
        -- 已访问/对方，跳过
      else
        return {}                -- 遇到空点 → 有气，不死
      end
    end
  end
  return dead
end

-- handle_move: 落子 + 提子 + 自杀/打劫判定
function handle_move(board, move, color)
  local nb = deepcopy(board); nb[move.y][move.x] = color
  local killed = {}
  for each neighbor n of move:
    killed += get_dead_group(nb, n, opponent)
  local suicide = get_dead_group(nb, move, color)
  if #killed == 0 and #suicide > 0 then return board, nil end  -- 自杀
  local ko_spot = nil
  if #killed == 1 and #suicide == 1 then ko_spot = killed[1] end
  for each k in killed: nb[k.y][k.x] = 0                        -- 提子
  return nb, ko_spot
end
```

### 决策 3 — 打劫用 simple ko

- `killed.size==1 && suicide.size==1 → ko_spot = killed[0]`（单子打劫形状）
- 落子前校验 `move == ko_spot` → 非法
- **上一手为 pass 时劫禁解除**（`passes > 0` 时放行）——与围棋"禁止立即回提"本意一致
- **superko**（禁止任何局面重复）先不做：需 Zobrist 哈希（Lua 随机表固定种子麻烦），后续可加

### 决策 4 — 终局：中国数子（area），双方连过 → 客户端本地数子一致 → 终局

- **过手 PASS**：任一方可过，`passes += 1`；`passes >= 2`（双方各过一次）→ 请求终局
- **数子**：连过后客户端本地数子（子+空，不判死/不贴目）→ 发 `WIN(area={black,white})`
- **服务端比对**：需收到**两个不同 device_id** 的 `WIN` 且双方 `area` 值一致 → 记 winner 终局；只有一方发 / 值不一致 → 忽略（等待重新协商）
- 不贴目（休闲对局，点数为整数），后续可加贴目选项

---

## 3. Lua 状态机（`go_script.dart` 里的 `kGoScript`）

沿用 reversi 骨架（`on_init/join/leave/ACK/DEAL/MOVE/RESIGN/RESET`），新增 `PASS` 与 `WIN(area)`：

### 状态机

```
CreateRoom → state="lobby"      房主 = host
JoinRoom   → state 不变          第 2 个进入
ACK × 2    → state="ready"      双方 ACK
DEAL(host) → state="playing"    房主点开始；黑方=host（先手）
MOVE       → state 不变          服务端校验+提子+记 ko，追加 history
PASS       → state 不变          passes += 1；≥2 → ended
RESIGN     → state="ended"      认输，对手胜
WIN        → state="ended"      客户端数子一致后声明
RESET(host) → state="lobby"     房主重新开始
```

### context 字段

- `host_id` / `black_player_id`（=host，黑先手）
- `players` : {device_id: alias, ...}
- `history` : [{x, y, isBlack, captured}, ...] — 唯一权威落子序列（含 pass:true 条目）
- `captures` : {black: N, white: N} — 双方提子数
- `ko_spot` : {x, y} | nil — 当前打劫点
- `passes` : int — 连续过手计数
- `size` : int — 棋盘尺寸（默认 9）
- `ready` : {device_id: true, ...}
- `winner` : "black"|"white"|nil
- `action_permissions` : {action_key → role_rule}

### action_permissions

```lua
ACK    = "any",
DEAL   = "host",
MOVE   = "current_player",
PASS   = "current_player",
RESIGN = "any",
WIN    = "any",              -- 数子声明，双方都可能发（幂等）
RESET  = "host",
```

---

## 4. 客户端 Dart

### 文件结构（方案 A：`lab/demos/go_lua/` 多文件）

```
lib/lab/demos/go_lua/
├── go_script.dart        # kGoScript — Lua 状态机（服务端权威）
├── go_engine.dart        # GoRoom 封装 + Snapshot 便捷读取 + 棋盘重建 + 数子 + atari
├── go_board.dart         # GoBoardWidget — 9×9 网格线棋盘 + 星位 + 落子 + 最后一步 + 预览
├── go_constants.dart     # kGoSize=9 / relayUrl / 布局常量
└── widgets.dart          # LobbyEntryPage + OnlineGamePage
lib/lab/demos/go_lua_demo.dart   # DemoPage 注册（slug: 'go-lua', DemoType.game）
```

### go_engine.dart 核心

```dart
/// 单步落子记录（与服务端 history 条目同构）
class GoMove { int x; int y; bool isBlack; int captured; bool isPass; ... }

/// 棋盘状态：每格 0=空 / 1=黑 / 2=白。坐标 board[y][x]。
typedef GoBoard = List<List<int>>;

class GoRoom {
  final RoomHandle handle;
  bool get isBlack;       // 服务端 black_player_id
  bool get isHost;        // 服务端 host_id
  Future<void> ack() / deal() / reset() / move(GoMove) / pass() / resign() / declareWin(area);
  // Snapshot 便捷读取
  static List<GoMove> rebuildMoves(Snapshot?);
  static GoBoard rebuildBoard(List<GoMove>);      // 从 history 重放（含提子）
  static ({int black, int white}) detectArea(GoBoard);  // 中国数子（子+空）
  static bool isBlackTurn(List<GoMove>);          // 与服务端一致：pass 占槽位，(moves.length % 2)==0 为黑回合
  static bool canPerform(String action, Snapshot?, {isBlack, isMyTurn, isHost});
}
```

### go_board.dart 核心

`GoBoardWidget` — 9×9 网格线棋盘（对齐 gomoku 的 `_GridPainter` 思路，但棋子画在交点）：
- 棋盘背景 → `context.boardColors.background`
- 网格线/星位 → `context.boardColors.gridLine`
- 黑白子 → `context.boardColors.player1Stone / player2Stone`（深=黑/浅=白，对齐 gomoku）
- 最后一步标记 → `context.boardColors.lastMove`
- 合法落点提示 → `context.boardColors.hint`（半透明圆点）
- **atari 高亮** → 客户端本地算 `liberties==1` 的群 → 该群子加红描边（纯展示）

### widgets.dart 核心

- `LobbyEntryPage`：对齐 gomoku_lua —— 昵称（复用 `LuaGameAlias`）+ 房间号 → `tryJoinOrCreate`
- `OnlineGamePage`：
  - 阶段：lobby（等待对手+准备）/ playing（对战中）/ ended（终局）
  - 对战中：顶部回合条（轮到谁 + 提子数「黑吃×3 白吃×2」）、中央棋盘（点击→待确认→确认）、底部栏（**过手 PASS** / 认输 / 退出）
  - atari 提示：客户端本地算 `liberties==1` 的群 → 红描边
  - 终局：双方连过 → 客户端本地数子 → 发 WIN → 显示「黑 60 / 白 49」+ 再来一局

---

## 5. 交互与 UI（对齐 gomoku_lua）

- **Lobby**：昵称（复用 `LuaGameAlias`）+ 房间号 → `tryJoinOrCreate` → ACK × 2 → DEAL（房主开始）
- **对战中**：顶部回合条（轮到谁 + 提子数）、中央棋盘、底部栏（过手/认输/退出）
- **落子**：点击空点 → 待确认 → 确认 → 发 MOVE
- **atari 提示**：客户端本地算 `liberties==1` 的群 → 该群子半透明红标
- **终局**：双方连过 → 客户端本地数子 → 双方发 `WIN(area)` → 服务端比对一致 → 记 winner → 显示「黑 60 / 白 49」+ 再来一局
- **音效**：复用 `PieceSound.instance.play()`（落子）
- **主题**：棋盘走 `context.boardColors`，UI 面板走 `BoardTheme.of(context)`，无裸 hex

---

## 6. 游戏中心登记

`const_game_center.dart` 加一条（`slug` 与 DemoPage.slug 一致）：

```dart
'go-lua': GameMeta(
  categories: {GameCategory.multiplayer, GameCategory.board},
  icon: Icons.circle_outlined,
  gradient: [Color(0xFF1E293B), Color(0xFF475569)],  // 黑白灰
  mode: '联机双人',
  pattern: GameArtPattern.grid,
),
```

---

## 7. 测试与验证

- `flutter analyze` 零 error（孤儿文件也覆盖）
- **规则正确性**：`handle_move` 在 Dart 侧复刻一份（`rebuildBoard` 重放含提子），与 Lua 同一套算法，用单元测试覆盖：
  - 提子（落子提掉无气群）
  - 自杀（禁止）
  - 打劫（simple ko 禁止回提）
  - 数子（detectArea 子+空）
- CI（GitHub Actions）build apk 验证编译

---

## 8. 可选加味点（本次范围外，可后续加）

- **A. 悔棋 UNDO**（reversi 有，围棋可做「撤回一步」）
- **B. 贴目**（中国规则黑贴 3.75 或 7.5，让黑先手公平）
- **C. 5×5 / 9×9 双尺寸可选**（房间创建时选）
- **D. 领先指示**（顶部显示当前领先方）
- **E. superko**（禁止任何局面重复，需 Zobrist 哈希）
