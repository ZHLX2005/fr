// lib/lab/demos/team_card/team_card_script.dart
//
// 团建卡牌 (kTeamCardScript) Lua 状态机脚本 — 跟随它的 demo。
// 业务脚本（谁是卧底 / 狼人杀）归 demo 自己，不放 net_p2p。

/// 团建卡牌 Lua 脚本（kTeamCardScript）
///
/// ## 状态机（精简：去 ACK/单一 START/三区架构）
///
/// ```
///   CreateRoom           → state="lobby"     大厅等待，三区入座
///   on_join 玩家区满     → 自动调 do_start() → state="playing"
///   on_action_START      → 房主一键发牌（玩家区必须满）
///   on_action_RESET      → state="lobby"     房主清空身份 + 回大厅
///   on_action_SET_ROLE_POOL → state="lobby"  房主上传角色池（lobby 阶段）
///   on_action_SIT        → 换区（lobby 阶段）房主可坐到玩家区参与游戏
///   on_action_HOST_MSG   → state="playing"  主持人给指定玩家发私信
/// ```
///
/// 玩家区满后服务端自动跑发牌（不需要 ACK）。主持人也可以凑齐前手动按 START。
///
/// ## 三区（host / player / spectator）
///
///   - `host_zone`         : 容量 1 — 房主监控席（默认入座）
///   - `player_zone`       : 容量 player_slots — 玩家（必须满员才能开局）
///   - `spectator_zone`    : 容量 0=无限 或 N — 旁观者（只看不发牌）
///
/// 房主默认进 host_zone；其他人默认进 player_zone（有空位）或 spectator_zone。
/// 房主可在 lobby 阶段用 SIT 把自己换到 player_zone 参与游戏；其他人可换到 spectator。
///
/// ## 主持人特权
///
///   - 发牌后，host_zone 的人可见 `c.assignments` 全部（其他区只看自己的）
///   - 可用 on_action_HOST_MSG 给指定玩家发私信（state=playing 时）
///   - 私信列表 `c.host_messages[]` 每条 `{from, to, text, at}`
///
/// ## context 字段
///
///   - `host_id`       : string, 房主 device_id（服务端权威）
///   - `roles`         : array of `{label, count}`, 上传的身份池
///   - `players`       : map device_id → alias
///   - `player_slots`  : int, 玩家区容量
///   - `spectator_slots`: int, 旁观区容量（0 = 无限）
///   - `zones`         : map device_id → "host"|"player"|"spectator"
///   - `assignments`   : map device_id → role（deal 后写入）
///   - `host_messages` : array of `{from, to, text, at}`（主持人私信）
///   - `max_players`   : 1 + player_slots + max(1, spectator_slots)
const String kTeamCardScript = r'''
-- 工具：列出本局可发牌的玩家 device_id 列表（仅 player zone）
function eligible_players(c)
  local ids = {}
  for did, _ in pairs(c.players) do
    if c.zones[did] == "player" then
      table.insert(ids, did)
    end
  end
  return ids
end

-- 工具：各区人数
function zone_counts(c)
  local h, p, s = 0, 0, 0
  for _, z in pairs(c.zones) do
    if z == "host" then h = h + 1
    elseif z == "player" then p = p + 1
    elseif z == "spectator" then s = s + 1 end
  end
  return h, p, s
end

-- 工具：玩家区容量
function player_zone_count(c)
  local _, p = zone_counts(c)
  return p
end

-- 工具：核心发牌逻辑（洗牌 + 写 assignments + 切 playing）
function do_start(c)
  local pool = {}
  for _, r in ipairs(c.roles) do
    for i = 1, (r.count or 0) do
      table.insert(pool, r.label)
    end
  end
  local playerIds = eligible_players(c)
  while #pool < #playerIds do
    if #c.roles == 0 then
      table.insert(pool, "?")
    else
      table.insert(pool, c.roles[#c.roles].label)
    end
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

-- 工具：换区容量检查（host 区固定 1，spectator 区按 spectator_slots 或无限）
function zone_has_room(c, target, exclude_did)
  local _, p, s = zone_counts(c)
  if target == "host" then
    local h = 0
    for did, z in pairs(c.zones) do
      if z == "host" and did ~= exclude_did then h = h + 1 end
    end
    return h < 1
  elseif target == "player" then
    return p < c.player_slots
  elseif target == "spectator" then
    -- spectator_slots == 0 视为无限
    return c.spectator_slots == 0 or s < c.spectator_slots
  end
  return false
end

on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.roles = p.roles or {}
  if #c.roles == 0 then
    c.roles = { { label = "卧底", count = 1 }, { label = "平民", count = 5 } }
  end
  c.player_slots = p.player_slots or 6
  c.spectator_slots = p.spectator_slots or 0   -- 0 = 无限旁观
  c.max_players = 1 + c.player_slots + math.max(c.spectator_slots, 1)
  c.zones = {}
  -- 房主默认入 host_zone（监控席；可 SIT 到 player_zone 参与游戏）
  c.zones[p.device_id] = "host"
  c.assignments = {}
  c.host_messages = {}
  state = "lobby"
  return c
end

on_join = function(c, p)
  c.players[p.device_id] = p.alias

  -- 默认入座规则：玩家区有空位 → player；否则 → spectator
  -- host 区不主动分配（只房主自己；房主想参加游戏用 SIT）
  local _, pcount = zone_counts(c)
  if pcount < c.player_slots then
    c.zones[p.device_id] = "player"
  else
    c.zones[p.device_id] = "spectator"
  end

  -- ★ 满即开：玩家区新到第 N 人 → 服务端自动 do_start
  if c.zones[p.device_id] == "player"
     and state == "lobby"
     and player_zone_count(c) == c.player_slots then
    do_start(c)
  end
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  c.zones[p.device_id] = nil
  if c.assignments ~= nil then
    c.assignments[p.device_id] = nil
  end
  return c
end

-- 房主一键发牌（玩家区满 + state=lobby）
on_action_START = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "lobby" then return c end
  if player_zone_count(c) ~= c.player_slots then return c end
  do_start(c)
  return c
end

-- 房主重置（清空 assignments + 回 lobby）
on_action_RESET = function(c, p)
  if c.host_id ~= p.device_id then return c end
  c.assignments = {}
  c.host_messages = {}
  state = "lobby"
  return c
end

-- 房主上传/更新身份池（仅 lobby 阶段有效）
on_action_SET_ROLE_POOL = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "lobby" then return c end
  if p.roles == nil or type(p.roles) ~= "table" then return c end
  c.roles = p.roles
  return c
end

-- 换区（lobby 阶段）：房主可从 host_zone 坐到 player_zone 参与游戏；
-- 其他人可换到 spectator 旁观。
on_action_SIT = function(c, p)
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local target = p.zone
  if target ~= "host" and target ~= "player" and target ~= "spectator" then
    return c
  end
  -- 房主可坐任何区；非房主不能坐 host_zone
  if target == "host" and p.device_id ~= c.host_id then return c end
  -- 目标区容量检查（排除自己当前占的区槽）
  if not zone_has_room(c, target, p.device_id) then return c end
  c.zones[p.device_id] = target
  return c
end

-- 主持人私信（仅 state=playing；只能 host_id 发送）
on_action_HOST_MSG = function(c, p)
  if state ~= "playing" then return c end
  if p.device_id ~= c.host_id then return c end
  if p.to == nil or type(p.to) ~= "string" then return c end
  if c.zones[p.to] ~= "player" then return c end  -- 只能发给玩家
  if p.text == nil or type(p.text) ~= "string" or p.text == "" then return c end
  if c.host_messages == nil then c.host_messages = {} end
  table.insert(c.host_messages, {
    from = p.device_id,
    to = p.to,
    text = p.text,
    at = os.time(),
  })
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_START", "on_action_RESET", "on_action_SET_ROLE_POOL",
    "on_action_SIT", "on_action_HOST_MSG",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_START = on_action_START,
  on_action_RESET = on_action_RESET,
  on_action_SET_ROLE_POOL = on_action_SET_ROLE_POOL,
  on_action_SIT = on_action_SIT,
  on_action_HOST_MSG = on_action_HOST_MSG,
}
''';