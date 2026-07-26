// lib/lab/demos/reversi_lua/reversi_script.dart
//
// 黑白翻转棋（Othello / Reversi）双人对战 Lua 状态机脚本。
//
// 与五子棋的差异：
//   - 棋盘 8x8 格子，落子在格子（不是交点）
//   - 落子必须能夹住对方至少 1 子（合法性校验放客户端，服务端存 history）
//   - 黑先手，轮到谁由 history 长度推导（偶数=黑方，奇数=白方）
//   - **black_player_id 与 host_id 解耦**：ACK × 2 → ready；DEAL 阶段服务端
//     随机选 host 或非 host 作为黑方（用户偏好落子前随机分配）
//   - 对称棋盘，无需镜像
//   - 悔棋（UNDO）：current_player 退一步 history（与五子棋不同）
//   - 胜负：客户端从 history 重建棋盘 + 跑核心引擎判定；满了/双方无合法步 → 发 WIN

/// 黑白翻转棋双人对战脚本 — kReversiScript
///
/// ## 状态机
///
/// ```
///    CreateRoom → state="lobby"     房主 = 服务端权威（创建者）
///    JoinRoom   → state 不变        第 2 个进入
///    ACK × 2    → state="ready"    双方 ACK
///    DEAL (host) → state="playing"  房主点开始；服务端随机分配 black_player_id
///    MOVE       → state 不变        追加一步落子 (x, y, isBlack)
///    UNDO       → state 不变        current_player 退一步 history
///    RESIGN     → state="ended"    认输（对手赢）
///    WIN        → state="ended"    客户端判定胜负后声明
///    RESET (host) → state="lobby"  房主重新开始（重新随机分配黑方）
/// ```
///
/// ## context 字段
///
///   - `host_id`           : string  房主 device_id（创建者）
///   - `black_player_id`   : string  随机分配的黑方 device_id；DEAL 时由服务端确定
///   - `players`           : {device_id: alias, …}
///   - `history`           : [{x, y, isBlack}, …]  唯一权威落子序列（isBlack=true=黑方）
///   - `ready`             : {device_id: true, …}
///   - `winner`            : "black"|"white"|nil
///   - `action_permissions`: {action_key → role_rule}
const String kReversiScript = r'''
-- 角色权限检查
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  -- current_player：由 history 最后一步推导当前轮到谁（黑先手）
  if rule == "current_player" then
    if #c.history == 0 then
      -- 游戏刚开始，黑方还没落过；黑方先手
      return p.device_id == c.black_player_id
    end
    local last = c.history[#c.history]
    -- 刚下完 last.isBlack → 轮到对方
    return (last.isBlack and p.device_id ~= c.black_player_id)
        or (not last.isBlack and p.device_id == c.black_player_id)
  end
  -- non_current_player：刚下完最后一步的人（WIN 声明用）
  if rule == "non_current_player" then
    if #c.history == 0 then return false end
    local last = c.history[#c.history]
    return (last.isBlack and p.device_id == c.black_player_id)
        or (not last.isBlack and p.device_id ~= c.black_player_id)
  end
  return false
end

on_init = function(c, p)
  c.host_id = p.device_id
  -- DEAL 阶段才确定 black_player_id（服务端随机分配）；init 时暂置 host。
  c.black_player_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.ready = {}
  c.history = {}
  c.max_players = p.max_players or 2
  c.action_permissions = {
    ACK    = "any",
    DEAL   = "host",
    MOVE   = "current_player",
    UNDO   = "current_player",
    RESIGN = "any",
    WIN    = "non_current_player",
    RESET  = "host",
  }
  state = "lobby"
  return c
end

on_join = function(c, p)
  if c.players[p.device_id] ~= nil then return c end
  local count = 0
  for _, _ in pairs(c.players) do count = count + 1 end
  if count >= c.max_players then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end
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
  if count >= c.max_players and aready >= count and state == "lobby" then
    state = "ready"
  end
  return c
end

on_action_DEAL = function(c, p)
  if not role_check(c, p, "DEAL") then return c end
  if state ~= "ready" then return c end
  -- ★ 服务端随机分配 black_player_id：50% 概率选 host，50% 选非 host
  local ids = {}
  for did, _ in pairs(c.players) do table.insert(ids, did) end
  if #ids < 2 then
    -- 异常兜底：单人时黑方=host
    c.black_player_id = c.host_id
  else
    -- math.random 在 gopher-lua 里有（标准库），返回 [0,1)
    c.black_player_id = (math.random() < 0.5) and ids[1] or ids[2]
  end
  state = "playing"
  return c
end

-- 落子：p.move = {x, y, isBlack}
-- 合法性校验（必须能夹住至少 1 子）放客户端，服务端只存历史。
on_action_MOVE = function(c, p)
  if not role_check(c, p, "MOVE") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local move = p.move
  if move == nil then return c end
  if move.x == nil or move.y == nil or move.isBlack == nil then return c end
  -- ★ 颜色校验：必须是 current_player 的颜色（current_player 由 history 推导）
  local curIsBlack
  if #c.history == 0 then
    curIsBlack = true
  else
    curIsBlack = not c.history[#c.history].isBlack
  end
  if curIsBlack ~= move.isBlack then return c end
  table.insert(c.history, move)
  return c
end

-- 悔棋：current_player 退一步 history（只撤自己刚下的那步）。
-- 校验：history 最后一步必须是 current_player 自己刚下的。
on_action_UNDO = function(c, p)
  if not role_check(c, p, "UNDO") then return c end
  if state ~= "playing" then return c end
  if #c.history == 0 then return c end
  local last = c.history[#c.history]
  -- 当前轮到 = 对方（last.isBlack 是 current_player 的对手）
  local curIsBlack
  if #c.history == 0 then
    curIsBlack = true
  else
    curIsBlack = not last.isBlack
  end
  -- last.isBlack 是"已落"那步的颜色；current_player 是"待落"那步的颜色
  -- 悔棋方必须就是 last 这步的落子方
  local lastMoverIsBlack = last.isBlack
  if lastMoverIsBlack then
    -- last 是黑方下的 → 悔棋方必须是黑方
    if p.device_id ~= c.black_player_id then return c end
  else
    -- last 是白方下的 → 悔棋方必须是白方
    if p.device_id == c.black_player_id then return c end
  end
  table.remove(c.history)
  return c
end

on_action_RESIGN = function(c, p)
  if not role_check(c, p, "RESIGN") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local blackId = c.black_player_id
  c.winner = (p.device_id == blackId) and "white" or "black"
  state = "ended"
  return c
end

on_action_WIN = function(c, p)
  if not role_check(c, p, "WIN") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local winner = p.winner
  if winner ~= "black" and winner ~= "white" then return c end
  local blackId = c.black_player_id
  local isFromBlack = (p.device_id == blackId)
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
  -- 黑方重新随机分配（新局公平）
  local ids = {}
  for did, _ in pairs(c.players) do table.insert(ids, did) end
  if #ids >= 2 then
    c.black_player_id = (math.random() < 0.5) and ids[1] or ids[2]
  else
    c.black_player_id = c.host_id
  end
  state = "lobby"
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_ACK", "on_action_DEAL", "on_action_MOVE",
    "on_action_UNDO", "on_action_RESIGN", "on_action_RESET", "on_action_WIN",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_ACK = on_action_ACK,
  on_action_DEAL = on_action_DEAL,
  on_action_MOVE = on_action_MOVE,
  on_action_UNDO = on_action_UNDO,
  on_action_RESIGN = on_action_RESIGN,
  on_action_RESET = on_action_RESET,
  on_action_WIN = on_action_WIN,
}
''';