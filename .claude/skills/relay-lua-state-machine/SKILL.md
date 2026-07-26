---
name: relay-lua-state-machine
description: Relay-v3 Lua 状态机接入指南。新增一个互联网房间业务（聊天、卡牌、白板、投票、协作…）时使用。描述后端元函数契约、前端闭环套路、Lua 脚本模板、state 转换规范、错误案例。识别"我要实现一个新业务""写一个 Lua 房间脚本""加一个 action 类型"时触发。
---
# Relay-v3 Lua 状态机 — 前端闭环接入指南



> 本文档是 `relay-v3` 协议的**业务可编程层**接入参考。理解了 v3 协议后，业务复杂度只取决于 Lua 脚本 — **后端无需改 Go 代码**。

## 何时读哪个 ref

| ref | 何时读取 |
|---|---|
| [[team-card-lobby-pattern]] | **实现"大厅 + 身份 + 就绪门 + 双区"类业务时**（团建卡牌、狼人杀、谁是卧底、观众制直播、回合制棋牌）。包含 4 个可组合机制：私有身份分配（`assignments`）、ACK/UNACK 就绪门、双区槽位（`zones`）、SIT 换区。还含前端 `TeamCardRoom` 语义封装 + widget 分文件模板。 |
| [[role-aware-board-mirror]] | **实现"对称对战棋盘"类业务时**（围追堵截/国际象棋/围棋/五子棋/军棋——双方都看到"自己在底部"）。这是**逐元素翻转决策**，不是统一镜像：触摸坐标手动镜像、确认按钮移出 flip 层、终局消息用角色推。含完整翻转决策表 + 围追堵截 4 轮 fix 踩坑时间线。 |
| [[server-authoritative-client-state]] | **所有 v3 互联网房间业务的"上游原则"**——客户端"我是谁/谁赢了/谁是房主"不能自查，必须用服务端权威字段（`host_id`/`top_player_id`/`winner`）。含 3 类典型自查 bug 案例（imTop/WIN/isHost）+ 乐观更新合法用法 + 围追堵截踩坑时间线。**任何业务先读这一篇。** |
| [[action-permission-table]] | ⚠️ **成熟期优化，前期不推荐**——当 action 多（≥5）、规则稳定、出现"无效按钮"UX bug 时才引入。把"谁能做哪个 action"收敛到服务端 `c.action_permissions` 单一表 + `role_check` helper，客户端 `canPerform(action)` 单点消费，零特判代码。是 [[server-authoritative-client-state]] 的"怎么做"落地篇。含 5 种角色规则 + 服务端/客户端双保险 + 迁移步骤 + ★何时引入判断。 |
| [[versus-game-room-template]] | **从 0 实现一个 2 人互联网对战游戏**（象棋/围棋/五子棋/围追堵截/井字棋）时通读。端到端模板：六件套文件结构 + Lua 状态机/权限表设计 + 四阶段 UX 交互（lobby/ready/playing/ended）+ 胜负判定模式 + widget 抽象边界 + 新游戏 checklist。综合调用前 4 个 ref。 |

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
| **团建卡牌/狼人杀（大厅+身份+就绪+双区）** | 参照 [[team-card-lobby-pattern]] — 全套 4 机制 | 0 |
| **对称对战棋盘（围追堵截/象棋/围棋，双方镜像视角）** | 参照 [[role-aware-board-mirror]] — 逐元素翻转决策表 | 0 |
| **任何 v3 互联网房间**（必读） | **先用 [[server-authoritative-client-state]]** —— 角色/状态用服务端字段，不用客户端自查 | 0 |
| **有按钮/操作约束的房间**（成熟期） | [[action-permission-table]] —— action_permissions 表驱动（前期 action 少时用特判更快） | 0 |
| **双人对战游戏**（象棋/围棋/五子棋/围追堵截/井字棋——2 人轮流 + 有胜负） | 参照 [[versus-game-room-template]] —— 端到端模板（六件套 + 状态机 + 四阶段 UX + 胜负判定 + 新游戏 checklist），综合调用以上 4 个 ref | 0 |

**零 Go 代码改动。**

---

## 12. 调试套路

| 现象                            | 排查                                                             |
| ------------------------------- | ---------------------------------------------------------------- |
| CreateRoom 400                  | 检查 handler 是否顶层全局                                        |
| CreateRoom "lua parse error"    | 注释里不能有`--[[ ]]` 等特殊字符（Dart 字符串嵌入 Lua 时避免） |
| ApplyAction 422                 | 检查 type 是否带前缀；context 是否有 nil 索引                    |
| ApplyAction 422 "unknown event" | on_action_<TYPE></type> 名字不在 `definition.functions` 列表里 |
| WS 立刻断开                     | 检查是否 Join 过；device_id 一致                                 |
| snapshot 不更新                 | 检查 Lua handler 是否`return c`                                |

诊断工具：项目 `.tool/relay-v3-simulator/scripts/prove_bug.py` 验证后端 / `relay_v3_sim.py` 跑全流程。
