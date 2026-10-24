---
name: C00-RelayLua路由
description: FR Relay-v3 Lua 状态机接入的大序列与唯一总路由。维护 RelayLua 内部 Ca/Cb/Cc 子序列和全部成员；新建互联网房间业务、联机游戏或多人大厅时使用。
---

# C00 — RelayLua 大序列路由

> C 在 FR 工程总路由中只代表 RelayLua。其内部包含 Ca（通用契约）、Cb（双人对战游戏）和 Cc（多人大厅）三个子序列；成员使用 `Ca01`/`Cb01`/`Cc01` 命名，子序列自身不设 `00`。**本文件集中维护所有子序列路由。**

## Ca — Relay-v3 通用原则与契约

| 文档 | 何时读取 |
|---|---|
| [[Ca01-服务端权威状态]] | 所有 Relay-v3 房间业务先读：身份、房主、胜负必须消费服务端权威字段时 |
| [[Ca02-命名与GameMeta]] | 新增/修改 v3 联机 demo、slug、分类或目录登记时 |
| [[Ca03-Action权限表]] | action 数量增长、规则稳定并需统一权限表时；这是成熟期优化 |

## Cb — Relay-v3 双人对战游戏

| 文档 | 何时读取 |
|---|---|
| [[Cb01-双人对战房间模板]] | 从零实现双人互联网对战游戏时；这是本子序列端到端入口 |
| [[Cb02-社交房间号模式]] | 用户输入共享房间号、抢占房主或区分撞号/满员时 |
| [[Cb03-角色棋盘镜像]] | 双方视角需分别看到“自己在底部”的棋盘时 |
| [[Cb04-棋盘手势模式]] | 需要点选/二次落子/拖动/预览的棋盘交互时 |

## Cc — Relay-v3 多人大厅业务

| 文档 | 何时读取 |
|---|---|
| [[Cc01-团队卡牌大厅模式]] | 实现身份分配、就绪门、多个区域或玩家换区的多人业务时 |

## 上下游规则

- 任何 v3 业务先读 Ca01；新增游戏登记再读 Ca02。
- Cb01 综合调用 Ca01/Ca03、Cb02/Cb03 和 Cc01；只在匹配的业务变体时加载相应成员。
- C 序列只含 RelayLua；Timetable/WebRTC 等其他子系统不属于本序列，也不要因编号相似混入。

---

---

## 1. 一句话理解

**后端是通用 Lua 解释器 + 状态广播器**，前端上传一段 Lua = 定义一个房间的完整业务逻辑。

- 上传 Lua 脚本 → 后端 `gopher-lua` 编译 + 缓存
- 客户端通过 `ApplyAction` 触发 Lua 事件
- Lua 修改 `context` + `state`
- 后端自动生成 `snapshot` 全量推给所有 WS 订阅者
- 客户端**只渲染**，零合并算法

---

## 2. 元函数 vs 自定义函数 — 核心边界

| 类型                               | 函数                                   | 触发者                                                             | 能否自定义                                           |
| ---------------------------------- | -------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------- |
| **元函数**（3 个，固定）     | `on_init`, `on_join`, `on_leave` | `CreateRoom` / `JoinRoom` / `LeaveRoom` / WS 断线 / 房间 TTL | **必须实现** — 涉及后端 socket/broadcast 逻辑 |
| **自定义函数**（N 个，任意） | `on_action_<X>`                      | 客户端`ApplyAction(type="X", ...)`                               | **完全自定义** — 业务方随便写                 |

> 🟡 **关键洞察**：元函数的"必须实现"指的不是必须写某个业务逻辑 — 而是你必须 `c.xxx = {...}` 初始化房间数据结构（比如 `players`、`messages`、`board`）。不想处理的 `on_join` 留空函数即可。

---

## 3. 元函数契约

### 3.1 `on_init(context, params)`

| 触发                                                        | params 字段                   |
| ----------------------------------------------------------- | ----------------------------- |
| `CreateRoom` 创建房间时，**整个房间生命周期只一次** | 来自`initial_params` 请求体 |

**职责**：初始化房间全局数据结构，包括：

```lua
on_init = function(c, p)
  c.players = {}           -- ✅ 必须：参与者列表（即使是空）
  c.max_players = p.max_players or 4
  c.messages = {}          -- ✅ 必须：业务数据
  state = "lobby"          -- ✅ 关键：state 全局变量
  return c
end
```

### 3.2 `on_join(context, params)`

| 触发                                                                     | params                 |
| ------------------------------------------------------------------------ | ---------------------- |
| HTTP`POST /join` / `CreateRoom` 后自动 join 自己 / 重连 grace window | `{device_id, alias}` |

```lua
on_join = function(c, p)
  c.players[p.device_id] = p.alias  -- ✅ 必须更新玩家列表
  return c
end
```

### 3.3 `on_leave(context, params)`

| 触发                         | params.reason      |
| ---------------------------- | ------------------ |
| HTTP`POST /leave` 主动离开 | `"graceful"`     |
| WS 断连 5 秒未重连           | `"disconnect"`   |
| 服务端踢人（脚本触发）       | `"kicked"`       |
| 房间 TTL 过期清理            | `"room_evicted"` |

```lua
on_leave = function(c, p)
  c.players[p.device_id] = nil
  return c
end
```

> 💡 **reason 区分**：业务层可以做差异处理，例如 `"kicked"` 时把玩家状态保留为"已被踢"。

---

## 4. 自定义动作 — `on_action_<TYPE>`

### 命名规则

```
客户端 type:"X"        →  服务端查 on_action_X
type:"action_X" ❌      →  on_action_action_X（不存在，422）
```

### ⚠️ `p.device_id` 从哪来 —— 服务端**不注入**，必须客户端自己带

**契约（2026-10-20 真实 relay e2e 实测定案）**：

- 服务端把 action 的 `params` **原样透传**给 Lua handler，**不会**把请求里的
  `source_device_id` 自动合并进 `params`。
- 客户端 `RoomHandle.applyAction` 会先注入 `device_id` 再合并业务参数
  （`lib/core/net_engine/relay_v3/relay_v3_transport.dart`），Lua 因此读到
  `p.device_id`。**注意**：当前合并顺序允许业务参数覆盖 `device_id`，
  且该字段是客户端输入而非服务端身份证明——Lua 的权限判断只应视作
  客户端自报身份；跨设备信任/防伪需服务端按已验证连接身份校验（待服务端来源）。

- **失败模式极其隐蔽**：如果 action 的 `params` 里没有 `device_id`，
  Lua 里 `c.ready[p.device_id] = true` 会因为 **table index is nil** 抛错 →
  服务端**照常返回 HTTP 200**，但**快照原封不动** → 表现为「点了没反应」。
  更糟的是 `c.players[p.device_id]` 读 nil 不报错，直接 `return c` 静默跳过，
  整个准备门永远打不开。

- **写线下 e2e 探针（Python / curl）时必须手动补 `params.device_id`**：

  ```python
  json={"type": "ACK",
        "params": {"device_id": device, **params},
        "source_device_id": device}
  ```

  漏了它 → 所有带 `p.device_id` 的 handler 静默失效，而请求仍可能返回
  HTTP 200、快照不变（极易误判为“已生效”）。
  现役探针/测试见 `.tool/relay-room-tester/` 与 `test/core/net_engine/relay_v3_transport_test.dart`。

### 示例：完整业务（扑克游戏）

```lua
on_action_BET = function(c, p)
  c.bets = c.bets or {}
  c.bets[p.device_id] = p.amount
  if c.pot == nil then c.pot = 0 end
  c.pot = c.pot + p.amount
  state = "betting"  -- state 全局变量驱动阶段
  return c
end

on_action_DEAL = function(c, p)
  -- 发牌逻辑：每个玩家分配牌
  c.hands = c.hands or {}
  for did, _ in pairs(c.players) do
    c.hands[did] = { draw(c.deck) }  -- 假设 c.deck 已 on_init 准备
  end
  state = "playing"
  return c
end
```

> 💡 改业务 = **新增一个 `on_action_<X>` 函数 + 在 `definition.functions` 列表声明**。Go 代码一行不动。

---

## 5. 全局变量 `state` — Lua 状态机的"阶段码"

> 🟡 **核心**：snapshot **顶层**的 `state` 字段 = Lua 全局变量 `state`（**不是** `context.state`）。

### Flutter 端检测用：

```dart
handle.snapshots.listen((snap) {
  if (snap.state == 'playing') {
    // 切换到游戏 UI
  }
});
```

### 常见阶段模式

| Lua 脚本        | state 序列                                   |
| --------------- | -------------------------------------------- |
| 大厅等待 + 聊天 | `"lobby"` → `"playing"`                 |
| 回合制游戏      | `"lobby"` → `"playing"` → `"ended"`  |
| 投票            | `"lobby"` → `"voting"` → `"tallied"` |

### ⚠️ 必踩坑：忘记写 `state = "..."`

```lua
on_action_START = function(c, p)
  c.started = true      -- ❌ 只设 context.started，state 永远是 ""
  return c              -- ❌ Flutter 永远检测不到 snap.state 变化
end

on_action_START = function(c, p)
  c.started = true
  state = "playing"     -- ✅ 全局 state 也要改
  return c
end
```

---

## 6. `context` vs `state` 的区别

| 字段          | 位置                | 含义                                         | Flutter 读法          |
| ------------- | ------------------- | -------------------------------------------- | --------------------- |
| `state`     | snapshot 顶层       | **房间阶段**（lobby/playing/ended）    | `snap.state`        |
| `context.x` | snapshot.context 内 | **业务数据**（players/messages/board） | `snap.context['x']` |

**权威规则**：snapshot **唯一真相，零合并**。前端只 render。

---

## 7. 特殊返回值（高级特性）

| `context.xxx = ...`                                | 服务端反应                    |
| ---------------------------------------------------- | ----------------------------- |
| `context.force_leave = {"device_id_2"}`            | 踢 device_id_2，断 WS（4403） |
| `context.rejected_join = {["device_id_1"] = true}` | 拒绝该设备 join（409）        |

**🟡 易错**：`force_leave` 必须是**数组 `{"d2"}`**，不能用 map `{[d2]=true}`（静默失效）。

---

## 8. 完整可运行模板（大厅聊天版）

```lua
on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.max_players = p.max_players or 8
  c.started = false
  c.messages = {}
  state = "lobby"
  return c
end

on_join = function(c, p)
  c.players[p.device_id] = p.alias
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  return c
end

on_action_START = function(c, p)
  if c.host_id ~= p.device_id then return c end
  c.started = true
  state = "playing"
  return c
end

on_action_CHAT = function(c, p)
  table.insert(c.messages, p)
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_START", "on_action_CHAT",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_START = on_action_START,
  on_action_CHAT = on_action_CHAT,
}
```

> 🟡 **必须**：函数先顶层定义为全局，再在 `return {}` 表里**引用**——不能直接匿名写在表里（compile 失败：no global function of that name）。

---

## 9. Flutter 端调用套路

```dart
import 'package:xiaodouzi_fr/core/net_p2p/scripts/lobby_chat_script.dart';  // 默认大厅聊天
// 或：import 'package:xiaodouzi_fr/lab/demos/<biz>/<biz>_script.dart';  // 业务脚本随 demo 走

final transport = RelayV3Transport(
  relayUrl: 'http://47.110.80.47:8988',
  alias: 'Alice',
  deviceId: 'unique-device-id',
);

final handle = await transport.createRoom(
  script: kMyBizScript,  // 直接传 Lua 字符串
  initialParams: {'device_id': 'Alice', 'alias': 'Alice'},
  maxPlayers: 4,
);

handle.snapshots.listen((snap) {
  if (snap.state == 'playing') startBizUI(snap);
});

// 触发业务事件
await handle.applyAction(
  type: 'CHAT',
  params: {'text': 'Hello', 'alias': 'Alice'},
);
```

> 💡 Lua 脚本写在 Dart 字符串里（`r'''...'''`），上传到后端就完事。改业务 = 改脚本字符串。

---

## 10. 错误案例（已踩过的坑）

| # | 错误                                                               | 后果                                                   | 正确做法                                           |
| - | ------------------------------------------------------------------ | ------------------------------------------------------ | -------------------------------------------------- |
| 1 | `on_action_START` 只改 `c.started = true`                      | Flutter 永远检测不到开始                               | 同时`state = "playing"`                          |
| 2 | Go 后端`CreateRoom` 没把 `max_players` 注入 `initial_params` | Lua`p.max_players` 始终 nil → fallback 8            | 后端必须注入；或前置 DTO 转化                      |
| 3 | `force_leave = {[d2]=true}`（map 形式）                          | 静默不生效                                             | `force_leave = {"d2"}`（数组）                   |
| 4 | handler 写在`return {}` 表里而非顶层全局                         | CreateRoom 400                                         | 先顶层`on_X = function...end`，表里引用          |
| 5 | `type: "action_CHAT"` 加了前缀                                   | 后端查`on_action_action_CHAT` → 422                 | `type: "CHAT"`（不加前缀）                       |
| 6 | 没 Join 就连 WS                                                    | WS 4400`device not registered`                       | CreateRoom 路径必须先 join 自己                    |
| 7 | Flutter 在 lobby`dispose()` 里 `handle.dispose()`              | 聊天页发消息时`_snapshotsCtrl` 已关 → `Bad state` | lobby 释放权，handle 转移给 caller                 |
| 8 | JSON 数字解析`as int?` 直接 cast                                 | `double` 返回 null                                   | 用`int.tryParse()` / `(v as num).toInt()` 兼容 |
| 9 | 用`subscribe(topic)` + 合并流还原状态                            | 顺序错乱、晚加入丢消息                                 | 直接`handle.snapshots.listen` 全量替换           |
| 10 | action 的 `params` 里没带 `device_id`                        | **HTTP 200 但快照不变** —— 带 `p.device_id` 的 handler 静默失效 | 客户端 `RoomHandle.applyAction` 已注入；线下探针要手动补（见 §4） |

---

## 11. 业务迁移矩阵

| 场景     | 加什么                                              | 改什么 |
| -------- | --------------------------------------------------- | ------ |
| 聊天室   | `on_action_CHAT` + `c.messages`                 | 0      |
| 棋牌     | `on_action_MOVE/ATTACK/END` + `c.board`         | 0      |
| 协作白板 | `on_action_DRAW` + `c.paths[]`                  | 0      |
| 投票     | `on_action_VOTE` + `c.votes{}` `c.options[]`  | 0      |
| 抢答     | `on_action_BUZZ` + `c.first_buzz`、`c.winner` | 0      |
| 多人拼图 | `on_action_PLACE` + `c.board_state[][]`         | 0      |
| **团建卡牌/狼人杀（大厅+身份+就绪+双区）** | 参照 [[Cc01-团队卡牌大厅模式]] — 全套 4 机制 | 0 |
| **对称对战棋盘（围追堵截/象棋/围棋，双方镜像视角）** | 参照 [[Cb03-角色棋盘镜像]] — 逐元素翻转决策表 | 0 |
| **任何 v3 互联网房间**（必读） | **先用 [[Ca01-服务端权威状态]]** —— 角色/状态用服务端字段，不用客户端自查 | 0 |
| **有按钮/操作约束的房间**（成熟期） | [[Ca03-Action权限表]] —— action_permissions 表驱动（前期 action 少时用特判更快） | 0 |
| **双人对战游戏**（象棋/围棋/五子棋/围追堵截/井字棋——2 人轮流 + 有胜负） | 参照 [[Cb01-双人对战房间模板]] —— 端到端模板 + `GameLobbySpec`/`GameLobbyPage`，综合调用 [[Ca01-服务端权威状态]] / [[Ca03-Action权限表]] / [[Cb02-社交房间号模式]] / [[Cb03-角色棋盘镜像]] / [[Cc01-团队卡牌大厅模式]] | 0 |
| **社交场景双人对战（双方输入同一房间号，谁先到谁是房主）** | 参照 [[Cb02-社交房间号模式]] —— 服务端 `requested_code` + Lua `rejected_join` + 客户端 `tryJoinOrCreate` + 撞号/满员 409 区分提示 | 0 |

**零 Go 代码改动。**

---

## 12. 调试套路

| 现象                            | 排查                                                             |
| ------------------------------- | ---------------------------------------------------------------- |
| CreateRoom 400                  | 检查 handler 是否顶层全局                                        |
| CreateRoom "lua parse error"    | 注释里不能有`--[=[ ]=]` 等特殊字符（Dart 字符串嵌入 Lua 时避免） |
| ApplyAction 返回 422（unknown event） | 对照 action `type` 与 Lua `definition.functions`（无前缀 `on_action_<TYPE>`）；server 合同以服务端实现为准 |
| WS 立刻断开                     | 检查是否 Join 过；device_id 一致                                 |
| snapshot 不更新（HTTP 200） | ① handler 是否漏 `return c`；② `params.device_id` 是否缺失/被覆盖导致 Lua nil 索引静默失效；③ 服务端 Lua runtime 日志。此类失败不等于 422，需按“200 但快照未变”单独排查 |

诊断工具：现役工具 `.tool/relay-room-tester/emoji_e2e.dart`（原 `.tool/relay-v3-simulator/` 下 prove_bug.py / relay_v3_sim.py 已删除，2026-10 核对）。

---

### [2026-08-28] key_board_3 操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 把"图标对称"也独立成一个 ref | 和 `Cb03-角色棋盘镜像` 翻转决策表重复（都属于"棋盘对称"主题） | 在 `Cb03-角色棋盘镜像` 加 §4.5 一节，沿用其"翻转决策表"框架 |
| 把"手势层"塞进 `Cb01-双人对战房间模板` | 200+ 行让端到端模板臃肿，且未来"非对战棋盘"（围棋布局编辑器 / 解谜）也要用 | 独立 `Cb04-棋盘手势模式` ref，按"主题判据"（不是"内容多少"）拆 |
| 把"WS 检测 + 快照拉取"独立成 ref | 适用范围狭窄（只互联网对战），但 `Cb01-双人对战房间模板` 已经是"对战通用模板"，扩 §3.5 一节即可 | 扩 `Cb01-双人对战房间模板.md`，加 §3.5 WS 状态条 + §3.6 落子音 |
| 把"音效"独立成 ref | 所有 4 个对战游戏都用同一个 `PieceSound`，不是 relay-v3 协议相关 | 同样扩 §3.6，不另起 ref |

### [2026-08-28] codebase-optimizer 反思（4 个新经验）

#### good_eg：跨游戏通用 UI 组件抽到 core 子目录

**来源：** 在 jungle_chess_lua 内联实现 WS 状态条后，扩展到 7 个 Lua 房间游戏时，提取为 `RelayConnectionBar`。

**场景：** 同一段 UI / 逻辑（stream 订阅 + 防双击 + 失败 snackbar）在 4+ 个 demo 各写一遍时。

**做法（做对了什么）：**
- 抽出到 `lib/core/<subsystem>/<name>.dart`（本例 `lib/core/ui/game/relay_connection_bar.dart`——UI 件落全局组件目录 `lib/core/ui/game/`，2026-10-24 起）
- 自带 stream 订阅 + 状态管理（callers 0 状态代码）
- 在所有 demo 文件加 1 行 import + 1 行调用即接入（`<RelayConnectionBar(handle: widget.handle) />`）
- 适用范围 ≤ 5 个 demo 时**不要**硬抽——直接 inline；≥ 4 个时**应该**抽出来

**为什么不这么做会出问题：** 7 个 demo 每个写 30 行重复订阅代码 ≈ 200 行技术债，且 bug 修一处忘一处。

**关联：** 配合 [[Cb01-双人对战房间模板]] §3.5（WS 状态条）使用效果更好——该 ref 直接指向共享 widget。

#### bad_eg：照搬其他游戏的 UI 模式不校验语义 ❌

**来源：** 第一次做 jungle_chess_lua 时，照搬五子棋"两步确认门"。

**错误做法：** `onLocalMoveConfirmed → _pending 待确认 → 确认按钮 → _room.move`。

**后果：** 斗兽棋走法已由 `JungleEngine.getValidMoves` 校验，非法目标根本不响应 → 确认门是冗余 UX，用户多一次点击且 56px 槽位浪费屏幕。

**根因分析：** 没想清楚"是否需要确认"是由**游戏走法可逆性**决定的，不是由"我之前怎么做的"决定的。

**正确做法：**
- 落子不可逆 / 操作复杂（五子棋）：保留两步确认
- 走法靠引擎校验、非法目标已被拦截（斗兽棋 / 围棋 / 黑白翻转棋 / 政变）：**直接落子** + 拖动 + 点击两种交互共存

**预防：** 在 §3.3 playing 阶段文档里明确"是否需要确认"的两条决策路径。

#### bad_eg：复用引擎时不区分双方先手约定 ❌

**来源：** jungle_chess_lua 红蓝双方控制对方棋子 bug。

**错误做法：** 复用 `JungleEngine.createInitialState()`（LAN 蓝方先手），但 Lua 服务端约定 `top_player_id`（红方 / host）先走。

**后果：** 客户端 `GameState.currentTurn = blue`，但服务端判定 `current_player` 是 red → host 端触摸控制器 `piece.color == state.currentTurn` = `red == blue` = false → 反而能选蓝方棋子（对方的）。

**根因分析：** `createInitialState` 把"先手方"硬编码为 blue，没有参数化。

**正确做法：**

```dart
// core：保留原函数（LAN 向后兼容）
static GameState createInitialState() =>
    createInitialStateFor(firstTurn: PlayerColor.blue);

// core：参数化版本
static GameState createInitialStateFor({required PlayerColor firstTurn}) { ... }

// Lua 互联网版：显式 red 先手
static GameState rebuildBoard(List<JungleMoveRecord> history) {
  var s = JungleEngine.createInitialStateFor(firstTurn: PlayerColor.red);
  ...
}
```

**预防：** 共享引擎被多个上层（LAN / Lua / 教程）复用时，**先手方 / 任何"业务侧可选"参数必须参数化**，不能硬编码默认。

#### good_eg：自包含 widget 自带 stream 订阅

**来源：** `RelayConnectionBar` 的设计。

**场景：** UI 组件需要监听 `RoomHandle.closeEvents` + `snapshots` 来显示连接状态。

**做法：**
- widget 自带 `initState / dispose` 订阅 + cancel
- callers 只需要 `import + 用一次`（`<RelayConnectionBar(handle: widget.handle) />`）
- 不暴露内部状态给 parent（`_wsConnected` 是 private）

**为什么不这么做会出问题：** 如果 widget 暴露 `_wsConnected` 给 callers，7 个 demo 每个都要写 4 个状态字段 + 3 个 listener cancel，bug 同步成本高。

**关联：** [[Cb01-双人对战房间模板]] §3.5 直接引用此模式。

#### bad_eg：外层 GestureDetector + 内部 GestureDetector 双触发 ❌

**来源：** jungle_chess_lua 第二次修触摸 bug 时，外层自写 GestureDetector 把 `localPosition` 直接喂 `JungleTouchController`，同时 JungleBoard 内部也挂了一个。

**错误做法：**
```dart
// widget.dart 外面
Positioned.fill(child: GestureDetector(
  onTapDown: (d) => _touchController.onCellTap(_gameState, _canonicalIdx(d.localPosition)),
  ...
)),
// JungleBoard 内部还有
GestureDetector(onTapDown: (d) => ctrl.onCellTap(...))
```

**后果：** 两个回调都会触发 → 触摸状态错乱 → 选中/拖动/落子逻辑互相覆盖 → 用户体感是"按了没反应"。

**根因分析：** 没意识到 JungleBoard 已经自带 GestureDetector（当 `touchController != null` 时挂载）。

**正确做法：** 复用 JungleBoard **内部** 的 GestureDetector，让 `localPosition` 在 board-local 坐标系（不受外层 `Transform.flip` 影响）。删除外层 wrapper。

**预防：** 任何"在 widget 外层套 Listener / GestureDetector"的模式都要先**搜索基类是否已挂载**。详细决策表见 [[Cb04-棋盘手势模式]] §3.1。
