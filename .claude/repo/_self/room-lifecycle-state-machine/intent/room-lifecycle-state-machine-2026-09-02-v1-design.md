# Design: 房间生命周期状态机 v1

> **Date:** 2026-09-02
> **Topic:** room-lifecycle-state-machine
> **类型:** intent doc（预测设计）
> **版本:** v1（首版：setup/lobby/playing 三态 + waiting 排队入座）
> **状态:** 候选
> **核心问题:** 房间创建后立即可加入、配置靠"再建房间"实现——用生命周期状态机把"配置/开放/游戏"三个阶段隔离，从根源消灭二次建房间、配置失效、号码被覆盖、玩家提前进入四个 bug。

## 术语铁律（最容易搞混，先读这张表）

| 术语 | 字段 | 谁定 | 层 | 含义 |
| --- | --- | --- | --- | --- |
| **玩家区人数** | `c.player_slots` | 房主（setup/lobby 阶段 `SET_PLAYER_SLOTS`） | **Lua 业务层** | 玩家区（发牌对象）的容量。玩家区满 → 房主才能 START |
| **房间总人数** | `max_players`（transport 参数） | 后端系统（固定 8） | **transport 系统层** | 整个房间的硬上限，含三区总和 |
| 主持区 | `zones[did]="host"` | 房主专属座位 | Lua | 容量恒为 1，**不占玩家区名额** |
| 玩家区 | `zones[did]="player"` | 先到先得 | Lua | 容量 = `player_slots`，会被发牌 |
| 旁观区 | `zones[did]="spectator"` | 溢出者 | Lua | 容量 = 房间剩余空间（`max_players − 1 − player_slots`），**不占玩家区名额** |
| 等待区 | `zones[did]="waiting"` | 系统自动 | Lua | **仅 setup 阶段存在**，不占三区任何席位；OPEN 时自动入座 |

**恒等式**：`房间总人数（=8，后端硬上限） = 主持区(1) + 玩家区(player_slots) + 旁观区(剩余) [+ waiting(临时，不计入)]`

**❌ 历史错误（本次 bug 链的直接成因）**：
- ❌ 把 `player_slots` 当房间总人数用（导致"房主设 3 人但显示 8 槽"——8 是 transport 默认值混进来了）
- ❌ 把房主的主持区座位算进 `player_slots`
- ❌ 旁观者占玩家区名额
- ❌ waiting 玩家提前占玩家区席位（会让 `SET_PLAYER_SLOTS` 被"当前已坐人数"卡死）

## 一、状态机总览

```
CreateRoom（后端系统级 API，整个生命周期唯一一次）
    │  on_init: state="setup"，host 进主持区
    ▼
╔═════════════════════╗
║ "setup"  房主配置中  ║
╠═════════════════════╣
║ 非房主 join：       ║  ✅ 协议层加入成功
║   zones="waiting"   ║  （不占席位；UI 显示等待页）
║ SET_ROLE_POOL       ║  房主：身份池
║ SET_PLAYER_SLOTS    ║  房主：玩家区人数（无死锁，玩家区 0 人）
╚══════════╤══════════╝
           │ 房主点「开放房间」→ OPEN：
           │   ① state="lobby"
           │   ② waiting 逐一自动入座（先到先得进玩家区，
           │      溢出 → 旁观区；此时才检查 max_players）
           │   ③ lobby snapshot 广播 → 等待玩家 UI 自动进大厅
           ▼
╔═════════════════════╗
║ "lobby"  开放中      ║
╠═════════════════════╣
║ 新 join：            ║  正常直接入座（玩家区空 → player，
║                      ║  满 → spectator，达 max_players 拒绝）
║ SET_* 仍可用         ║  （带保护：新 player_slots ≥ 当前玩家区人数）
║ SIT 换区             ║  房主可坐玩家区亲自参与
╚══════════╤══════════╝
           │ 玩家区满 + 房主点「开始发牌」→ START → do_start
           ▼
╔═════════════════════╗
║ "playing" 游戏中     ║  玩家看自己身份 / 主持区看全部 / 旁观看全部
╠═════════════════════╣  HOST_MSG 主持人私信
╚══════════╤══════════╝
           │ RESET（房主）：清 assignments + host_messages
           ▼
      回 "lobby"（连续开局，玩家不退房）
```

## 二、Lua action 契约

| action | 谁能调 | 何阶段 | 行为 |
| --- | --- | --- | --- |
| （系统）`on_init` | — | 创建时 | `state="setup"`；`zones[host]="host"`；player_slots 取默认 |
| （系统）`on_join` | — | 任何 | `state=="setup"` 且非 host → `zones[did]="waiting"`；lobby → 正常入座（玩家区空则 player，满则 spectator；房间满由 transport `max_players` 层拒绝） |
| `OPEN` | host | setup only | 入座全部 waiting（先到先得 player，溢出 spectator）→ `state="lobby"` |
| `SET_ROLE_POOL` | host | setup + lobby | 覆写 `c.roles` |
| `SET_PLAYER_SLOTS` | host | setup + lobby | 改 `c.player_slots`；**lobby 阶段要求新值 ≥ 当前玩家区已坐人数**（setup 阶段玩家区恒 0，天然无约束） |
| `START` | host | lobby + 玩家区满 | 洗牌发牌 → `state="playing"` |
| `RESET` | host | playing | 清 assignments/messages → `state="lobby"` |
| `SIT` | 任何人 | lobby | 换区（host↔player 亲自参与；player↔spectator）；容量检查 |
| `HOST_MSG` | host | playing | 给指定玩家私信（append `c.host_messages[]`） |

**waiting 入座顺序**：Lua map（`c.players`）无序。v1 用"遍历顺序"即可（人数少，无感）；若要严格先到先得，后续加 `c.join_seq` 计数器（待定问题，见 §十）。

## 三、Flutter 流程映射（UI 结构不变，只改语义）

| 阶段 | 页面 | 驱动 |
| --- | --- | --- |
| 入口 | `LobbyEntryPage`（alias + code → `tryJoinOrCreate`） | 房间创建一次；code 全程不变 |
| host 配置 | `HostPoolConfigView`（现 SetupPage 改造） | **只对现有 handle 发 action**（SET_ROLE_POOL / SET_PLAYER_SLOTS / OPEN），**绝不 `tryJoinOrCreate`** |
| 等待 | `PlayingView` 内分支：`state=="setup" && !isHost` | 渲染等待页（转圈 + "房主正在配置中，房间开放后自动入座"）；lobby snapshot 到达自动切换（snapshot 驱动，零额外代码） |
| 大厅/游戏 | `PlayingView` 现有逻辑 | 三区卡 + START 按钮 + 皇冠照旧 |

**409 映射新增一条**：transport 层 `max_players`（房间总 8 人）满 → "房间已满"。setup 阶段不再产生 409（waiting 不设限，理论上也受 max_players 约束）。

## 四、关键决策（含选型说明）

| # | 决策 | 理由 | 备选（为何不选） |
| --- | --- | --- | --- |
| 1 | waiting 排队而非 409 拒绝 | 挂机自动进 vs 反复重试；waiting 不占席位 → `SET_PLAYER_SLOTS` 无死锁 | 409 拒绝：体验差且房主改人数会被"已坐人数"卡死 |
| 2 | OPEN 时集中入座 | 一次 action 完成 state 切换 + 入座，原子性好 | join 时立即入座：占席位，与房主配置并发冲突 |
| 3 | 房间只创建一次 | code 稳定、无双房、配置天然作用于本房间 | 重建房间：正是原 bug 链根源 |
| 4 | `player_slots` 与 `max_players` 分层 | 业务容量（可调）与系统容量（硬上限）职责分离 | 混用：显示错、设置失效（已踩） |
| 5 | RESET 回 lobby 不回 setup | 连续开局，玩家免重进 | 回 setup：每次都要重新开放，团建场景太重 |

## 五、代码骨架（示意，非实现）

```lua
on_init = function(c, p)
  c.host_id = p.device_id
  c.zones = { [p.device_id] = "host" }
  c.player_slots = p.player_slots or 8   -- 业务默认；房主 setup 阶段可改
  state = "setup"                         -- ★ 新：不再直接进 lobby
  return c
end

on_join = function(c, p)
  c.players[p.device_id] = p.alias
  if state == "setup" then
    c.zones[p.device_id] = "waiting"      -- ★ 排队，不占席位
    return c
  end
  -- lobby 正常入座（现有逻辑）
end

on_action_OPEN = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "setup" then return c end
  local seated = player_zone_count(c)
  for did, z in pairs(c.zones) do
    if z == "waiting" then
      if seated < c.player_slots then
        c.zones[did] = "player";  seated = seated + 1
      else
        c.zones[did] = "spectator"
      end
    end
  end
  state = "lobby"
  return c
end
```

## 六、改动范围（影响面）

| 模块 | 现状 | 改后 | 影响 |
| --- | --- | --- | --- |
| `team_card_script.dart` Lua | `on_init` 直接 `state="lobby"`；无 OPEN/SET_PLAYER_SLOTS | 三态 + waiting + OPEN + SET_PLAYER_SLOTS | 核心 |
| `engine.dart` | `start/reset/setRolePool/sit/hostSend` + tryJoinOrCreate | 加 `open()`、`setPlayerSlots()`；删 `maxPlayers` 计算（固定 8） | 小 |
| `widgets.dart` SetupPage | `_create()` 调 `tryJoinOrCreate`（二次建房间 bug 源头） | 改为对现有 handle 发 SET_* + OPEN | 核心 |
| `widgets.dart` PlayingView | 无等待分支 | `state=="setup" && !isHost` → 等待页 | 小 |
| `team_card_lua_demo.dart` | HostPoolConfigView 传 handle | 不变（handle 透传已是现状） | 无 |

## 七、验收标准

| # | 验证项 | 方法 |
| --- | --- | --- |
| 1 | 房间只创建一次，code 永不变 | 设备 A 输入 "ABCD" 进入配置 → 完成开放 → 显示房间号仍为 ABCD |
| 2 | waiting 排队 | A 配置中，B/C 加入 → B/C 显示等待页；A 点开放 → B/C 自动出现在大厅 |
| 3 | 玩家区人数真正生效 | A 设 player_slots=3 → 大厅显示"玩家区 0/3"；第 3 人进入后 START 亮起 |
| 4 | 术语不混 | player_slots=3 时：大厅三区卡显示 玩家区 3 槽（非 8）；房间总人数最多 8（第 9 人 join 被拒） |
| 5 | 溢出进旁观 | waiting 有 5 人、player_slots=3 → 开放后 3 人玩家区 + 2 人旁观区 |
| 6 | 连续开局 | playing → RESET → 回 lobby，玩家列表不丢，可再 START |
| 7 | 主持区皇冠 | 任意阶段房主头像带皇冠（含坐到玩家区/旁观区时） |

## 八、待用户拍板的决策

| # | 决策 | 推荐 |
| --- | --- | --- |
| 1 | waiting 严格先到先得需要 `join_seq` 计数器吗 | v1 不加（遍历序即可，人少无感）；出现投诉再加 |
| 2 | 等待页是否显示排队序号（"你是第 2 位"） | v1 不显示；文案仅"房主正在配置中" |

## 九、参考

- 意图文档：`room-lifecycle-state-machine-2026-09-02-intent.md`
- relay-v3 协议：`.claude/skills/relay-lua-state-machine/SKILL.md`（元函数契约、zones、rejected_join）
- bug 链现场：commits cc7b28cf → 30020e6d（三区/皇冠/入口等前置重构），本设计为语义收口层
