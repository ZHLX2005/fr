// lib/lab/demos/team_card/team_card_script.dart
//
// 团建卡牌 (kTeamCardScript) Lua 状态机脚本 — 跟随它的 demo。
// 业务脚本（谁是卧底 / 狼人杀）归 demo 自己，不放 net_p2p。
//
// 设计文档：.claude/repo/_self/room-lifecycle-state-machine/
// 术语铁律：玩家区人数（player_slots，业务设置）≠ 房间总人数（max_players，后端系统 8）

/// 团建卡牌 Lua 脚本（kTeamCardScript）— 房间生命周期状态机版
///
/// ## 状态机
///
/// ```
/// CreateRoom → state="setup"（房主配置中，host 进主持区）
///   非房主 join → zones="waiting"（排队，不占三区席位）
///   SET_ROLE_POOL / SET_PLAYER_SLOTS（房主配置）
///   OPEN（房主点开放）→ waiting 集中入座（先到先得玩家区，溢出旁观）→ state="lobby"
/// state="lobby"（开放中，join 直接入座；SET_* 仍可改；SIT 换区）
///   START（房主 + 玩家区满）→ do_start → state="playing"
/// state="playing"（游戏中；晚进者 → spectator；HOST_MSG 主持人私信）
///   RESET（房主）→ 清 assignments/messages → state="lobby"（连续开局）
/// ```
///
/// ## 术语铁律
///
/// - `player_slots`：玩家区容量（业务层，房主 SET_PLAYER_SLOTS 可调；玩家区满才能 START）
/// - 房间总人数：transport 层 max_players（后端系统固定 8）= 主持(1)+玩家+旁观
/// - waiting：setup 阶段临时区，不占任何席位
///
/// ## context 字段
///
/// - `host_id`        : 房主 device_id（服务端权威）
/// - `roles`          : [{label, count}] 身份池
/// - `players`        : map device_id → alias
/// - `player_slots`   : 玩家区容量
/// - `spectator_slots`: 旁观区容量（0 = 无限）
/// - `zones`          : map device_id → "host"|"player"|"spectator"|"waiting"
/// - `assignments`    : map device_id → role（START 后写入）
/// - `host_messages`  : [{from, to, text, at}] 主持人私信
const String kTeamCardScript = r'''
-- ══════════ 工具函数 ══════════

function eligible_players(c)
  local ids = {}
  for did, _ in pairs(c.players) do
    if c.zones[did] == "player" then
      table.insert(ids, did)
    end
  end
  return ids
end

function zone_counts(c)
  local h, p, s, w = 0, 0, 0, 0
  for _, z in pairs(c.zones) do
    if z == "host" then h = h + 1
    elseif z == "player" then p = p + 1
    elseif z == "spectator" then s = s + 1
    elseif z == "waiting" then w = w + 1 end
  end
  return h, p, s, w
end

function player_zone_count(c)
  local _, p = zone_counts(c)
  return p
end

-- 核心发牌：构造池 + Fisher-Yates 洗牌 + 写 assignments + 切 playing
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

-- 换区容量检查（host 区固定 1；spectator 0=无限；player 按 player_slots）
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
    return c.spectator_slots == 0 or s < c.spectator_slots
  end
  return false
end

-- ══════════ 元函数 ══════════

on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.roles = p.roles or {}
  if #c.roles == 0 then
    c.roles = { { label = "卧底", count = 1 }, { label = "平民", count = 7 } }
  end
  -- ★ 术语铁律：player_slots 是玩家区容量（业务），不是房间总人数（后端 8）
  c.player_slots = p.player_slots or 8
  c.spectator_slots = p.spectator_slots or 0   -- 0 = 无限旁观
  -- 房间总人数（三区总和，含主持）由 Lua 强制（后端 transport 不查 max_players）
  c.max_players = p.max_players or 8
  c.zones = {}
  c.zones[p.device_id] = "host"                -- 房主进主持区
  c.assignments = {}
  c.host_messages = {}
  c.offline = {}                               -- playing 掉线标记（座位/身份保留）
  state = "setup"                              -- ★ 新：先配置，不直接进 lobby
  return c
end

on_join = function(c, p)
  -- 房间总人数门禁只对新面孔生效（归来者本来就在名单里）
  if c.players[p.device_id] == nil then
    local count = 0
    for _ in pairs(c.players) do count = count + 1 end
    if count >= c.max_players then
      c.rejected_join = c.rejected_join or {}
      c.rejected_join[p.device_id] = true
      return c
    end
  end

  c.players[p.device_id] = p.alias
  if c.offline ~= nil then c.offline[p.device_id] = nil end

  -- ★ 归来者：座位还在 → 原样恢复（不再分配；防止撞进"含自己的满员
  -- 玩家区"被误判成 spectator）
  if c.zones[p.device_id] ~= nil then
    return c
  end

  if state == "setup" then
    -- 配置阶段：排队等待，不占三区席位（房主改 player_slots 无死锁）
    if p.device_id ~= c.host_id then
      c.zones[p.device_id] = "waiting"
    end
    return c
  end

  -- 新人 playing 晚进：只旁观（未发过牌的人不干扰对局）
  if state == "playing" then
    c.zones[p.device_id] = "spectator"
    return c
  end

  -- lobby：正常入座（玩家区空 → player；满 → spectator）
  local _, pcount = zone_counts(c)
  if pcount < c.player_slots then
    c.zones[p.device_id] = "player"
  else
    c.zones[p.device_id] = "spectator"
  end
  return c
end

on_leave = function(c, p)
  -- ★ 离开只改状态标记：任何名单/座位/身份都不动。
  -- 重连是常态（暂时退出/杀进程/切后台），凭 device_id 回来即恢复原位；
  -- "暂时离线"仅作为玩家的展示状态。
  -- 座位长期占用由房主 RESET 时释放（掉线未归者退场）。
  c.offline = c.offline or {}
  c.offline[p.device_id] = true
  return c
end

-- ══════════ 自定义 action ══════════

-- 房主开放房间：waiting 集中入座（先到先得玩家区，溢出旁观）→ lobby
on_action_OPEN = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "setup" then return c end
  local seated = player_zone_count(c)
  for did, z in pairs(c.zones) do
    if z == "waiting" then
      if seated < c.player_slots then
        c.zones[did] = "player"
        seated = seated + 1
      else
        c.zones[did] = "spectator"
      end
    end
  end
  state = "lobby"
  return c
end

-- 房主上传/更新身份池（setup + lobby）
on_action_SET_ROLE_POOL = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "setup" and state ~= "lobby" then return c end
  if p.roles == nil or type(p.roles) ~= "table" then return c end
  c.roles = p.roles
  return c
end

-- 房主修改玩家区/旁观区容量（setup + lobby；lobby 带人数保护）
on_action_SET_PLAYER_SLOTS = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "setup" and state ~= "lobby" then return c end
  if type(p.player_slots) ~= "number" or p.player_slots < 1 then return c end
  if type(p.spectator_slots) ~= "number" or p.spectator_slots < 0 then return c end
  -- lobby 保护：新玩家区容量不能小于当前已坐玩家数（setup 阶段玩家区恒 0，天然自由）
  if state == "lobby" then
    local _, pcount = zone_counts(c)
    if p.player_slots < pcount then return c end
  end
  c.player_slots = p.player_slots
  c.spectator_slots = p.spectator_slots
  return c
end

-- 房主一键发牌（lobby + 玩家区满）
on_action_START = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "lobby" then return c end
  if player_zone_count(c) ~= c.player_slots then return c end
  do_start(c)
  return c
end

-- 房主重置（清 assignments/messages → lobby，连续开局）
on_action_RESET = function(c, p)
  if c.host_id ~= p.device_id then return c end
  if state ~= "playing" then return c end
  -- 掉线未归者彻底退场（释放座位；归来的已在 on_join 清掉 offline 标记）
  if c.offline ~= nil then
    for did, _ in pairs(c.offline) do
      c.players[did] = nil
      c.zones[did] = nil
    end
    c.offline = {}
  end
  c.assignments = {}
  c.host_messages = {}
  state = "lobby"
  return c
end

-- 换区（lobby）：房主 host↔player 亲自参与；其他人 player↔spectator
on_action_SIT = function(c, p)
  if state ~= "lobby" then return c end
  if c.players[p.device_id] == nil then return c end
  local target = p.zone
  if target ~= "host" and target ~= "player" and target ~= "spectator" then
    return c
  end
  if target == "host" and p.device_id ~= c.host_id then return c end
  if not zone_has_room(c, target, p.device_id) then return c end
  c.zones[p.device_id] = target
  return c
end

-- 主持人私信（playing；只能发给玩家区）
on_action_HOST_MSG = function(c, p)
  if state ~= "playing" then return c end
  if p.device_id ~= c.host_id then return c end
  if p.to == nil or type(p.to) ~= "string" then return c end
  if c.zones[p.to] ~= "player" then return c end
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
    "on_action_OPEN", "on_action_SET_ROLE_POOL", "on_action_SET_PLAYER_SLOTS",
    "on_action_START", "on_action_RESET", "on_action_SIT", "on_action_HOST_MSG",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_OPEN = on_action_OPEN,
  on_action_SET_ROLE_POOL = on_action_SET_ROLE_POOL,
  on_action_SET_PLAYER_SLOTS = on_action_SET_PLAYER_SLOTS,
  on_action_START = on_action_START,
  on_action_RESET = on_action_RESET,
  on_action_SIT = on_action_SIT,
  on_action_HOST_MSG = on_action_HOST_MSG,
}
''';