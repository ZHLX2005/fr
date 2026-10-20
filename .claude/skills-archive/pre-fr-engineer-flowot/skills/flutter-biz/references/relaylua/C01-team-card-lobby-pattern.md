# team-card-lobby-pattern — 大厅/身份/换区 通用模式

> 从 team_card 团建卡牌沉淀。适用于 **有大厅阶段 + 需要就绪投票 + 玩家/旁观区分** 的房间业务。

包含四个可组合的机制：

1. **私有身份**（`assignments` map）— 每人只看自己的牌
2. **ACK/UNACK 就绪门**（`ready` map + `all_ready` 判断）— 全员就绪房主才能开始
3. **双区槽位**（`zones` map + `player_slots`/`spectator_slots`）— 房间容量按区分配
4. **SIT 换区**（`on_action_SIT`）— 客户端主动切换所属区

---

## 1. 私有身份分配（DEAL）

### 数据结构

```lua
c.assignments = {}          -- device_id → role_label
c.roles = { {label, count}, ... }   -- 房主上传的身份池
```

### 权威分配 = 服务端洗牌

**关键**：随机分配必须在 Lua 里执行（`math.random`），客户端只读结果。分给谁什么牌**除了那个人自己**，谁都看不到（客户端从 snapshot 只读自己的 key）。

```lua
on_action_DEAL = function(c, p)
  if c.host_id ~= p.device_id then return c end   -- 仅房主
  if not all_ready(c) then return c end           -- 全员就绪才发

  -- 构造身份池
  local pool = {}
  for _, r in ipairs(c.roles) do
    for i = 1, (r.count or 0) do table.insert(pool, r.label) end
  end

  -- 洗牌（Fisher–Yates）
  local playerIds = eligible_players(c)
  while #pool < #playerIds do
    table.insert(pool, c.roles[#c.roles].label)   -- 池不够就补最后一个
  end
  if #pool >= 2 then
    for i = #pool, 2, -1 do
      local j = math.random(i)
      pool[i], pool[j] = pool[j], pool[i]
    end
  end

  -- 写 assignments
  c.assignments = {}
  for i, did in ipairs(playerIds) do
    c.assignments[did] = pool[i] or "?"
  end

  state = "playing"
  return c
end
```

### Flutter 端读取

```dart
String? myRole(Snapshot? snap, String deviceId) {
  final a = snap?.context['assignments'];
  if (a is! Map) return null;
  return a[deviceId]?.toString();
}

// UI 只渲染自己的
if (myRole(snap, deviceId) case final role?) {
  return IdentityCard(role: role);
}
```

> ⚠️ **反模式**：不要在客户端做"我知道所有人身份但只显示自己的" — 服务端权威意味着别人的 role 你根本拿不到。

---

## 2. ACK / UNACK 就绪门

### 目的

强制"人凑齐 + 人人点了准备"再让房主开始，避免误触。

### 数据结构

```lua
c.ready = {}   -- device_id → true（未 ack 就没这个 key）
```

### 判断函数（含区规则）

```lua
function is_required(c, did)
  if c.players[did] == nil then return false end
  if c.zones[did] ~= "player" then return false end   -- 旁观区不参与就绪判断
  return true
end

function all_ready(c)
  for did, _ in pairs(c.players) do
    if is_required(c, did) and c.ready[did] ~= true then return false end
  end
  return true
end
```

### handler

```lua
on_action_ACK = function(c, p)
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = true

  -- 门槛 1：玩家区必须满员
  local pcount = 0
  for _, z in pairs(c.zones) do
    if z == "player" then pcount = pcount + 1 end
  end
  if pcount < c.player_slots then return c end

  -- 门槛 2：全员 ready
  if all_ready(c) and state == "lobby" then state = "ready" end
  return c
end

on_action_UNACK = function(c, p)
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = nil
  if state == "ready" then state = "lobby" end   -- 降级
  return c
end
```

### state 转换

```
lobby ──ACK 全员且区满──▶ ready ──DEAL──▶ playing
  ▲                        │
  └──── UNACK / SIT 打破 ───┘
```

### Flutter 端按钮切换

```dart
final myReady = ((snap.context['ready'] as Map?)?[deviceId]) == true;

myReady
  ? OutlinedButton.icon(onPressed: onUnack, label: Text('取消准备'))
  : OutlinedButton.icon(onPressed: onAck,   label: Text('准备好了'));
```

### 常见坑

| 坑 | 后果 | 正确做法 |
|---|---|---|
| ACK 后没检查区容量 | 1 个玩家 ACK 就 ready 了 | ACK handler 里判 `pcount < player_slots` |
| UNACK 后没降级 state | UI 仍显示"就绪"，房主能点发牌 | `if state == "ready" then state = "lobby" end` |
| 旁观区玩家能 ACK | 界面出现无意义按钮 | Flutter 端 `_amSpectator ? null : onAck` 隐藏 |
| SIT 换区不清 ready | 换区后仍算 ready，行为不直觉 | `on_action_SIT` 里 `c.ready[p.device_id] = nil` |

---

## 3. 双区槽位（zones）

### 目的

同一房间既有"参与者"又有"旁观者"，容量分开定，行为分开：
- 玩家区 → 参与游戏，会被发牌，需要 ACK
- 旁观区 → 只看戏，不发牌，不需要 ACK，发牌后看到所有人身份

### 数据结构

```lua
c.player_slots = p.player_slots or 2       -- 玩家区容量
c.spectator_slots = p.spectator_slots or 0 -- 旁观区容量
c.max_players = c.player_slots + c.spectator_slots
c.zones = {}   -- device_id → "player"|"spectator"
```

### on_init 默认入座策略

```lua
-- 房主：有旁观区就默认旁观（让出玩家位）；没旁观区就进玩家区
if c.spectator_slots > 0 then
  c.zones[p.device_id] = "spectator"
else
  c.zones[p.device_id] = "player"
end
```

### on_join 空位查找

```lua
on_join = function(c, p)
  c.players[p.device_id] = p.alias
  local pcount, scount = 0, 0
  for did, z in pairs(c.zones) do
    if did ~= p.device_id then
      if z == "player" then pcount = pcount + 1 else scount = scount + 1 end
    end
  end
  -- 优先玩家区，其次旁观区，都满则不分配（可选：房间应该在 max_players 层就拒绝）
  if pcount < c.player_slots then
    c.zones[p.device_id] = "player"
  elseif scount < c.spectator_slots then
    c.zones[p.device_id] = "spectator"
  end
  return c
end
```

### eligible_players 只看玩家区

```lua
function eligible_players(c)
  local ids = {}
  for did, _ in pairs(c.players) do
    if c.zones[did] == "player" then
      table.insert(ids, did)
    end
  end
  return ids
end
```

### 前端渲染

按 zone 过滤后分两卡片展示：

```dart
final playerEntries = players.entries.where((e) => zoneMap[e.key] == 'player');
final spectEntries  = players.entries.where((e) => zoneMap[e.key] == 'spectator');
```

发牌后：
- 玩家区自己 → 看 `_IdentityCard(role: myRole)`
- 旁观区任何人 → 看 `_SpectatorView(assignments: all)` 看所有人身份

---

## 4. SIT 换区

### 目的

lobby 阶段玩家可自己决定去哪个区。默认策略往往不合口味（想旁观的被塞进玩家区）。

### handler

```lua
on_action_SIT = function(c, p)
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local target = p.zone
  if target ~= "player" and target ~= "spectator" then return c end

  -- 目标区容量检查（排除自己占的槽）
  local occupied = 0
  for did, z in pairs(c.zones) do
    if did ~= p.device_id and z == target then occupied = occupied + 1 end
  end
  local limit = target == "player" and c.player_slots or c.spectator_slots
  if occupied >= limit then return c end   -- 满了不动

  -- 换区 + 清 ready + 可能降级 state
  c.zones[p.device_id] = target
  c.ready[p.device_id] = nil
  if state == "ready" and not all_ready(c) then state = "lobby" end
  return c
end
```

### Flutter 端调用套路

**方案 A：单按钮 toggle**（简单）

```dart
onMoveZone: _amSpectator
  ? () => _engine.sit(zone: 'player')
  : () => _engine.sit(zone: 'spectator'),
```

**方案 B：空槽可点**（更直观）— 玩家看到对方区的空槽 → 点击 → SIT 到对方区。适合槽位组件已经在渲染的场景。

### 常见坑

| 坑 | 后果 | 正确做法 |
|---|---|---|
| SIT 参数用 `type: "action_SIT"` 加前缀 | 服务端查 `on_action_action_SIT` → 422 | `type: "SIT"`（不加前缀，后端自动加） |
| SIT 换区后忘清 ready | 玩家换回来仍然 ready，绕过就绪门 | `c.ready[p.device_id] = nil` |
| SIT 换区后没检查降级 | ready 状态混乱 | `if state == "ready" and not all_ready(c) then state = "lobby"` |
| 目标区满时静默失败 | 用户点了没反应，以为按钮坏了 | 前端拿到 snapshot 后 zone 没变即视为失败，可 SnackBar 提示 |
| SIT 允许 `state == "playing"` 换区 | 游戏中乱换 | 首行 `if state == "playing" then return c end` |

---

## 5. 前端语义封装（TeamCardRoom）

把上面所有 `applyAction` 藏在语义方法后面，业务代码更清爽：

```dart
class TeamCardRoom {
  TeamCardRoom(this.handle);
  final RoomHandle handle;

  Future<void> ack()   => handle.applyAction(type: 'ACK',   params: const {});
  Future<void> unack() => handle.applyAction(type: 'UNACK', params: const {});
  Future<void> sit({required String zone}) =>
      handle.applyAction(type: 'SIT', params: {'zone': zone});
  Future<void> deal()  => handle.applyAction(type: 'DEAL',  params: const {});
  Future<void> reset() => handle.applyAction(type: 'RESET', params: const {});

  static Future<RoomHandle> create(RelayV3Transport t, {...}) => ...;
  static Future<RoomHandle> join(RelayV3Transport t, {required String code}) => ...;
}
```

配合 Snapshot 便捷读取（放在同一层）：

```dart
Map<String, String> extractStringMap(Snapshot? s, String key) { ... }
Map<String, bool>   extractReadyMap(Snapshot? s)              { ... }
String?             myZone(Snapshot? s, String deviceId)      { ... }
String?             myRole(Snapshot? s, String deviceId)      { ... }
```

业务层只用语义方法 + 便捷读取，不再直接接触 `applyAction` 和 `snapshot.context['xxx']`。

---

## 6. 完整模式选型指南

| 你的业务 | 需要哪些机制 |
|---------|-------------|
| 纯聊天/白板 | 无（`kChatOnlyScript` 够用） |
| 大厅等待 + 开始游戏 | 只加 ACK/UNACK |
| 团建卡牌类身份分配 | 全部四个：assignments + ACK/UNACK + zones + SIT |
| 观众制直播/答题 | zones + SIT（玩家/观众分开），不一定要 ACK |
| 回合制棋牌 | assignments（起始位置/手牌）+ ACK（准备就绪）+ 自定义 `on_action_MOVE` |
| 抢答/竞猜 | ready 用作"是否举手"，不需要 zones |

---

## 7. Lua 编写反复踩的坑（team_card 教训）

| 坑 | 现象 | 修复 |
|---|---|---|
| `c.spectators = {["d2"]=true}` map 写法 | Lua LTable → Go 转换后丢字段 | 用数组 `c.spectators = {"d2"}` |
| `on_init` 忘写 `state = "lobby"` | Flutter 检测不到大厅阶段 | 每个改状态的 handler 都要设 `state = "..."` |
| `on_join` 忘更新 `c.zones[did]` | 新加入者没区 | `on_join` 强制赋值一个 zone |
| ACK 后没检查 `pcount == player_slots` | 1 人 ACK 就进 ready | 门槛 1 必须写 |
| `on_action_DEAL` 后忘 `state = "playing"` | 洗完牌 UI 不切换 | DEAL 尾行 `state = "playing"` |
| `RESET` 忘清 `c.assignments` | 上局身份残留 | `c.assignments = {}` 必须清 |
| `c.roles[#c.roles].label` 池不够补最后一个 | 玩家多于池时崩溃 | 上面 DEAL 里的 while 循环兜底 |

---

## 8. 前端 Widget 组织建议

超过 400 行的 lab demo 一律拆到 `lab/demos/<name>/`：
- `constants.dart` — 持久化 + 常量 + 模型（RoleDef / RolePreset / NamedPreset / PresetLibrary）
- `engine.dart` — 业务语义封装（TeamCardRoom）+ Snapshot 便捷读取
- `widgets.dart` — 全部 UI 组件

入口 `<name>_demo.dart` 只留 `DemoPage` + 主 Scaffold，其余全 import。
