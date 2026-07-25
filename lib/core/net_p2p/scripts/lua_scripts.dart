// lib/core/net_p2p/scripts/lua_scripts.dart
//
// 所有 Lua 状态机脚本集中管理。
// 脚本是服务端权威的业务逻辑：客户端上传 → 后端 gopher-lua 执行 → snapshot 驱动。
//
// 按业务分类：
//   - lobbyChat：大厅等待 + 聊天（默认）
//   - ...扩展：可在同一文件追加新脚本

/// 大厅等待 + 聊天脚本（lobbyChat）
///
/// 包含两阶段状态机：
///   1. `lobby` — 房主建房，玩家加入等待，房主点"开始"
///   2. `playing` — 开始后切换到聊天模式
///
/// 状态 (state):
///   - "" (空) → 初始
///   - "lobby" → 大厅等待
///   - "playing" → 游戏中
///
/// context:
///   - `host_id` — 房主 device_id
///   - `players` — {device_id: alias, ...}
///   - `max_players` — 房间容量
///   - `started` — bool，是否已开始
///   - `messages` — 聊天消息列表
///
/// 事件类型 (ApplyAction type):
///   - `START` → 房主触发开始游戏
///   - `CHAT` → 发送聊天消息
///
/// ## 错误案例
///
/// | 错误写法 | 后果 | 正确写法 |
/// |----------|------|---------|
/// | `force_leave = {[d2]=true}` | 静默不生效 | `force_leave = {"d2"}` |
/// | handler 写在 return 表里而非全局 | CreateRoom 400 | handler 先顶层定义 `on_xxx=function...end` |
/// | `type: "action_CHAT"` | 后端再补 `action_` → 422 | `type: "CHAT"` |
///
/// ## handlers 必须是顶层全局函数
///
/// ```lua
/// -- ✅ 正确：先全局定义，再在 return 表里引用
/// on_init = function(c, p) ... end
/// return { definition = { functions = {"on_init"} }, on_init = on_init }
///
/// -- ❌ 错误：匿名函数不识别
/// return { definition = { functions = {"on_init"} },
///          on_init = function(c, p) ... end }
/// ```
const String kLobbyChatScript = r'''
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
  if c.host_id ~= p.device_id then
    return c
  end
  c.started = true
  state = "playing"
  return c
end

on_action_CHAT = function(c, p)
  table.insert(c.messages, p)
  return c
end

return {
  definition = { functions = { "on_init", "on_join", "on_leave", "on_action_START", "on_action_CHAT" } },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_START = on_action_START,
  on_action_CHAT = on_action_CHAT,
}
''';

/// 纯聊天脚本（无大厅阶段）
///
/// 适合不需要等待、直接聊天的场景（LAN 模式可直接对接）。
/// context: `{messages: [{text, alias, ...}]}`
const String kChatOnlyScript = r'''
on_init = function(c, p) c.messages = {}; return c end
on_join = function(c, p) return c end
on_leave = function(c, p) return c end
on_action_CHAT = function(c, p) table.insert(c.messages, p); return c end
return {
  definition = { functions = { "on_init", "on_join", "on_leave", "on_action_CHAT" } },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_CHAT = on_action_CHAT,
}
''';

/// 团建卡牌脚本（teamCard）
///
/// 类似"谁是卧底""狼人杀"的身份分配。
/// master 上传角色池 → 建房 → 玩家加入 → 选择入座玩家区 / 旁观区 →
/// 玩家区全员 ACK → master 点 DEAL → 服务端洗牌 + 写 `c.assignments` → snapshot 广播。
///
/// ## 状态机
///
/// ```
///   CreateRoom  → state="lobby"     大厅等待，两区入座
///   ACK         → state="ready"     玩家区玩家点"准备好了"
///   DEAL        → state="playing"   服务端洗牌 + 发牌
///   RESET       → state="lobby"     重新发牌（清空 ready）
///   SIT         → state不变         玩家点击目标区空位入座（换区）
/// ```
///
/// ## context 字段
///
///   - `host_id`       : string, 房主 device_id
///   - `roles`         : array of `{label, count}`, 上传的初始身份池
///   - `players`       : map device_id → alias
///   - `player_slots`  : int, 玩家区容量
///   - `spectator_slots`: int, 旁观区容量
///   - `zones`         : map device_id → "player"|"spectator"
///   - `ready`         : map device_id → true (玩家已点准备)
///   - `assignments`   : map device_id → role（deal 后写入）
///   - `max_players`   : player_slots + spectator_slots
///
/// ## API 调用
///
///   - `on_action_ACK`  params=`{}`  点准备 → 房主才能 DEAL
///   - `on_action_UNACK` params=`{}` 取消准备
///   - `on_action_SIT`  params=`{zone: "player"|"spectator"}`  入座目标区
///   - `on_action_DEAL` params=`{}`  服务端洗牌并发牌 → state="playing"
///   - `on_action_RESET` params=`{}`  重新发牌 → state="lobby"
///   - `on_action_SET_ROLE_POOL` params=`{roles: [...]}`  更新角色池（仅 host）
///
/// ## 注意事项
///
/// - 房间阶段：lobby (等待人数) → ready (等待准备) → playing
/// - max_players = player_slots + spectator_slots（总容量）
/// - 只发"玩家区"成员牌，"旁观区"成员看到所有人身份
/// - 默认进入玩家区；房主创建且有旁观区时默认进旁观区
/// - ACK 只要求"玩家区"成员全都 ready + 玩家区满员
const String kTeamCardScript = r'''
-- 工具函数：列出本局可发牌的玩家 device_id 列表（仅 player zone）
function eligible_players(c)
  local ids = {}
  for did, _ in pairs(c.players) do
    if c.zones[did] == "player" then
      table.insert(ids, did)
    end
  end
  return ids
end

-- 工具函数：检查玩家是否需要 ack（仅 player zone 且存在）
function is_required(c, did)
  if c.players[did] == nil then return false end
  if c.zones[did] ~= "player" then return false end
  return true
end

-- 工具函数：所有 player zone 的人是否都已 ack
function all_ready(c)
  for did, _ in pairs(c.players) do
    if is_required(c, did) and c.ready[did] ~= true then
      return false
    end
  end
  return true
end

on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.roles = p.roles or {}
  if #c.roles == 0 then
    c.roles = { { label = "平民", count = 4 } }
  end
  c.player_slots = p.player_slots or 2
  c.spectator_slots = p.spectator_slots or 0
  c.max_players = c.player_slots + c.spectator_slots
  c.zones = {}
  -- 房主：有旁观区就默认进旁观区，否则进玩家区
  if c.spectator_slots > 0 then
    c.zones[p.device_id] = "spectator"
  else
    c.zones[p.device_id] = "player"
  end
  c.assignments = {}
  c.ready = {}
  state = "lobby"
  return c
end

on_join = function(c, p)
  c.players[p.device_id] = p.alias
  c.ready[p.device_id] = nil
  -- 统计两区人数
  local pcount = 0
  local scount = 0
  for did, z in pairs(c.zones) do
    if did ~= p.device_id then
      if z == "player" then pcount = pcount + 1 else scount = scount + 1 end
    end
  end
  -- 默认进有空间的区：优先玩家区，其次旁观区
  if pcount < c.player_slots then
    c.zones[p.device_id] = "player"
  elseif scount < c.spectator_slots then
    c.zones[p.device_id] = "spectator"
  end
  -- 任意玩家 ready 被清 → 回退 lobby
  if state == "ready" and not all_ready(c) then state = "lobby" end
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  c.zones[p.device_id] = nil
  c.ready[p.device_id] = nil
  if c.assignments ~= nil then c.assignments[p.device_id] = nil end
  return c
end

-- 玩家点"准备好了"
on_action_ACK = function(c, p)
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = true
  -- 人数门槛：玩家区必须满员
  local pcount = 0
  for _, z in pairs(c.zones) do
    if z == "player" then pcount = pcount + 1 end
  end
  if pcount < c.player_slots then return c end
  if all_ready(c) and state == "lobby" then
    state = "ready"
  end
  return c
end

-- 玩家取消准备（lobby/ready 阶段有效）
on_action_UNACK = function(c, p)
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = nil
  if state == "ready" then state = "lobby" end
  return c
end

-- 玩家点击目标区空位入座
on_action_SIT = function(c, p)
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local target = p.zone
  if target ~= "player" and target ~= "spectator" then return c end
  -- 检查目标区是否有空位（排除自己当前占用的区槽）
  local occupied = 0
  for did, z in pairs(c.zones) do
    if did ~= p.device_id and z == target then occupied = occupied + 1 end
  end
  local limit = target == "player" and c.player_slots or c.spectator_slots
  if occupied >= limit then return c end
  c.zones[p.device_id] = target
  -- 换区时清 ready
  c.ready[p.device_id] = nil
  if state == "ready" and not all_ready(c) then state = "lobby" end
  return c
end

-- 房主发牌（必须 all_ready 且玩家区满员）
on_action_DEAL = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if not all_ready(c) then return c end

  local total = 0
  for _, r in ipairs(c.roles) do
    total = total + (r.count or 0)
  end

  local pool = {}
  for _, r in ipairs(c.roles) do
    for i = 1, (r.count or 0) do table.insert(pool, r.label) end
  end

  local playerIds = eligible_players(c)
  while #pool < #playerIds do
    table.insert(pool, c.roles[#c.roles].label)
  end

  if #pool >= 2 then
    for i = #pool, 2, -1 do
      local j = math.random(i)
      pool[i], pool[j] = pool[j], pool[i]
    end
  end

  c.assignments = {}
  for i, did in ipairs(playerIds) do
    c.assignments[did] = pool[i] or "?"
  end

  state = "playing"
  return c
end

on_action_RESET = function(c, p)
  if c.host_id ~= p.device_id then return c end
  c.assignments = {}
  c.ready = {}
  state = "lobby"
  return c
end

on_action_SET_ROLE_POOL = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "lobby" and state ~= "ready" then return c end
  if p.roles == nil or type(p.roles) ~= "table" then return c end
  c.roles = p.roles
  -- 不改 player_slots/spectator_slots
  c.ready = {}
  state = "lobby"
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_ACK", "on_action_UNACK", "on_action_SIT",
    "on_action_DEAL", "on_action_RESET", "on_action_SET_ROLE_POOL",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_ACK = on_action_ACK,
  on_action_UNACK = on_action_UNACK,
  on_action_SIT = on_action_SIT,
  on_action_DEAL = on_action_DEAL,
  on_action_RESET = on_action_RESET,
  on_action_SET_ROLE_POOL = on_action_SET_ROLE_POOL,
}
''';
