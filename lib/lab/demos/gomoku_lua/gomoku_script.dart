// lib/lab/demos/gomoku_lua/gomoku_script.dart
//
// 五子棋 (Gomoku) 双人对战 Lua 状态机脚本。
// 跟随它的 demo (lib/lab/demos/gomoku_lua/) — Lua 脚本随 demo 走，不放 net_p2p。
//
// 与围追堵截的差异：
//   - 棋盘 15x15 交点，落子在交点（不是格子）
//   - 只有落子（MOVE），没有墙、没有移动、没有悔棋
//   - 对称棋盘，无需镜像翻转
//   - 胜负 = 连五，客户端本地判定后发 WIN

/// 五子棋双人对战脚本 — kGomokuScript
///
/// ## 状态机
///
/// ```
///    CreateRoom → state="lobby"     Owner 等 Guest 加入
///    ACK × 2     → state="ready"    双方 ACK
///    DEAL (host) → state="playing"  游戏开始（黑方先手）
///    MOVE        → state不变        追加一步落子
///    RESIGN      → state="ended"    认输
///    WIN         → state="ended"    连五，记录 winner
/// ```
///
/// ## context 字段
///
///   - `host_id`          : string
///   - `black_player_id`  : string  权威字段 = 创建者（host），客户端据此推"我是黑/白"
///   - `players`          : {device_id: alias, …}
///   - `history`          : [{x, y, isBlack}, …]  唯一权威落子序列
///   - `ready`            : {device_id: true, …}
///   - `winner`           : "black"|"white"|nil
///   - `action_permissions` : {action_key → role_rule}  ★服务端约束单点真相
///
/// ## 落子记录
///
/// 每次 MOVE = `{x, y, isBlack}`，x/y ∈ [0, 14]，isBlack 表示这步是黑方还是白方。
/// 黑方先手（host = black_player_id）。
///
/// ## 镜像策略
///
/// 五子棋是**对称棋盘**（无终点方向），双方看同一棋盘，**不需要 Transform.flip**。
/// 角色（黑/白）仅决定先手顺序和落子颜色，不影响视觉。
const String kGomokuScript = r'''
-- 角色权限检查（与围追堵截同模式，见 action-permission-table ref）
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  -- current_player：由 history 最后一步推导当前轮到谁
  -- 黑方先手：history 空 → 轮到黑（black_player_id）
  -- 否则：与最后一步颜色相反的一方
  if rule == "current_player" then
    if #c.history == 0 then return p.device_id == c.black_player_id end
    local last = c.history[#c.history]
    local lastIsBlack = last.isBlack
    -- 上一步黑 → 轮到白（!= black_player_id）；上一步白 → 轮到黑
    return (lastIsBlack and p.device_id ~= c.black_player_id)
        or (not lastIsBlack and p.device_id == c.black_player_id)
  end
  return false
end

on_init = function(c, p)
  c.host_id = p.device_id
  -- 权威约定：host = 黑方（先手）。客户端用 black_player_id 推"我是黑/白"。
  c.black_player_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.ready = {}
  c.history = {}
  -- 动作权限表（★客户端按钮可点性的权威来源）
  c.action_permissions = {
    ACK    = "any",
    DEAL   = "host",
    MOVE   = "current_player",
    RESIGN = "any",
    WIN    = "current_player",
    RESET  = "host",
  }
  state = "lobby"
  return c
end

on_join = function(c, p)
  c.players[p.device_id] = p.alias
  c.ready[p.device_id] = nil
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  c.ready[p.device_id] = nil
  return c
end

on_action_ACK = function(c, p)
  if not role_check(c, p, "ACK") then return c end
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = true
  local count = 0
  for _, _ in pairs(c.players) do count = count + 1 end
  local aready = 0
  for _, v in pairs(c.ready) do if v then aready = aready + 1 end end
  if count >= 2 and aready >= count and state == "lobby" then
    state = "ready"
  end
  return c
end

on_action_DEAL = function(c, p)
  if not role_check(c, p, "DEAL") then return c end
  if state ~= "ready" then return c end
  state = "playing"
  return c
end

-- 落子：p.move = {x, y, isBlack}
on_action_MOVE = function(c, p)
  if not role_check(c, p, "MOVE") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local move = p.move
  if move == nil then return c end
  if move.x == nil or move.y == nil or move.isBlack == nil then return c end
  table.insert(c.history, move)
  return c
end

on_action_RESIGN = function(c, p)
  if not role_check(c, p, "RESIGN") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  -- 认输方 = 对手赢
  local blackId = c.black_player_id
  c.winner = (p.device_id == blackId) and "white" or "black"
  state = "ended"
  return c
end

-- 胜利声明：客户端本地连五判定后上报。双方都可能发（同一份 history），幂等。
on_action_WIN = function(c, p)
  if not role_check(c, p, "WIN") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local winner = p.winner
  if winner ~= "black" and winner ~= "white" then return c end
  local blackId = c.black_player_id
  local isFromBlack = (p.device_id == blackId)
  -- winner=black 只能由黑方声明；winner=white 只能由白方声明（防作弊）
  if winner == "black" and not isFromBlack then return c end
  if winner == "white" and isFromBlack then return c end
  c.winner = winner
  state = "ended"
  return c
end

on_action_RESET = function(c, p)
  if not role_check(c, p, "RESET") then return c end
  c.history = {}
  c.ready = {}
  c.winner = nil
  state = "lobby"
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_ACK", "on_action_DEAL", "on_action_MOVE",
    "on_action_RESIGN", "on_action_RESET", "on_action_WIN",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_ACK = on_action_ACK,
  on_action_DEAL = on_action_DEAL,
  on_action_MOVE = on_action_MOVE,
  on_action_RESIGN = on_action_RESIGN,
  on_action_RESET = on_action_RESET,
  on_action_WIN = on_action_WIN,
}
''';
