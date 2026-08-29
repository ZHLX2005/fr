// lib/lab/demos/jungle_chess_lua/jungle_lua_script.dart
//
// 斗兽棋 (Jungle Chess) 互联网双人对战 — Lua 状态机脚本。
//
// ## 状态机
//
// ```
//    tryJoinOrCreate → state="lobby"
//    ACK × 2         → state="ready"
//    DEAL (host)     → state="playing"
//    MOVE            → state 不变           追加一步
//    RESIGN          → state="ended"      认输
//    WIN             → state="ended"      胜负判定（客户端算 + 上报）
//    RESET (host)    → state="lobby"     房主再来一局
//
//    ## 掉线重连（关键）
//    on_leave (playing/ready) → state="waiting"  标记 c.disconnected[id]=true
//                                                       保留 history(不重置)
//    on_join (same device_id) → 取消 disconnected 标记
//                              若双方都 connected → state="playing"
//    on_join (新 device_id)   → waiting 期间拒绝
//    CANCEL_WAIT (host)       → 清空 history,回 lobby
// ```
//
// ## context 字段
//
//   - `host_id`           : string   创建者 device_id（服务端权威）
//   - `top_player_id`     : string   = host_id（视觉顶部方）
//   - `players`           : {device_id: alias, …}  ← 离线玩家也保留
//   - `disconnected`      : {device_id: true, …}   ← 离线的玩家标记
//   - `ready`             : {device_id: true, …}
//   - `history`           : [{from, to, piece, captured, isRiverJump, round}, …]
//   - `winner`            : "blue"|"red"|nil
//   - `max_players`       : number   上限（业务规则由 Lua 把守）
//   - `action_permissions`: {action → role_rule}
//
// ## 镜像策略（最关键点）
//
// 棋盘**完全对称**：服务端用规范坐标系（host = top_player，视觉 y=0 在上）。
// 客户端 host 端 `Transform.flip(flipY: true)` 把棋盘整体翻转，让自己棋子
// 在视觉底部。触摸坐标在指针回调里手动镜像（Listener 不在 flip 子树）。
// 确认按钮移出 flip 层 + 坐标镜像。终局消息用 `_imTop` 推"我方/对方"。

const String kJungleChessScript = r'''
-- 角色权限检查（与五子棋同模式）
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  -- current_player：当前轮到谁走（由 history 推导）
  if rule == "current_player" then
    if #c.history == 0 then return p.device_id == c.top_player_id end
    local last = c.history[#c.history]
    local lastTop = (last.color == "red")  -- 红方先手（host = top = red）
    return (lastTop and p.device_id ~= c.top_player_id)
        or (not lastTop and p.device_id == c.top_player_id)
  end
  -- non_current_player：刚下完最后一步的人
  if rule == "non_current_player" then
    if #c.history == 0 then return false end
    local last = c.history[#c.history]
    local lastTop = (last.color == "red")
    return (lastTop and p.device_id == c.top_player_id)
        or (not lastTop and p.device_id ~= c.top_player_id)
  end
  return false
end

on_init = function(c, p)
  c.host_id = p.device_id
  -- 权威约定：host = top = 红方（先手）。
  -- 棋盘坐标规范：y=0 是 top（视觉顶部，但 host 端翻转后 y=0 在视觉底部）。
  c.top_player_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.ready = {}
  c.disconnected = {}
  c.history = {}
  c.winner = nil
  c.max_players = p.max_players or 2
  c.action_permissions = {
    ACK          = "any",
    DEAL         = "host",
    MOVE         = "current_player",
    RESIGN       = "any",
    WIN          = "non_current_player",
    RESET        = "host",
    CANCEL_WAIT  = "host",
  }
  state = "lobby"
  return c
end

on_join = function(c, p)
  -- 关键修复：先识别"断线重连"（同 device_id）
  -- 同会话进程内的 WS 重连 → device_id 相同 → 复用 player + 取消 disconnected
  if c.players[p.device_id] ~= nil then
    c.disconnected[p.device_id] = nil
    -- 双方都 connected + 处于 waiting → 自动恢复到 playing
    if state == "waiting" then
      local allConnected = true
      for id, _ in pairs(c.players) do
        if c.disconnected[id] then allConnected = false; break end
      end
      if allConnected then
        state = "playing"
      end
    end
    return c
  end

  -- 新 device_id：waiting 期间拒绝（保留 history 给原对手重连）
  if state == "waiting" then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end

  -- lobby / ready：人数满则拒绝
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

-- 关键修复：不清空 history！
-- playing/ready 阶段任一方掉线 → 进入 "waiting" 状态，保留棋谱等待重连。
-- history/winner 只在 RESET / CANCEL_WAIT / ended 之后由房主显式清空。
on_leave = function(c, p)
  c.ready[p.device_id] = nil
  if state == "playing" or state == "ready" then
    -- 玩家保留在 players 中，只标记 disconnected
    -- （同会话 WS 重连时 on_join 能识别并恢复）
    state = "waiting"
    c.disconnected[p.device_id] = true
  elseif state == "waiting" then
    -- 已经 waiting 时再有玩家掉线：仅更新 disconnected 标记
    c.disconnected[p.device_id] = true
  elseif state == "lobby" then
    -- lobby 阶段：彻底移除（房主开了房但又主动退出,房间空置等 TTL）
    c.players[p.device_id] = nil
    c.disconnected[p.device_id] = nil
  elseif state == "ended" then
    -- 终局后有人离开：保持 ended（winner/history 留给对局回顾）
    -- 玩家也保留——终局画面上能看到对手的最终 alias
    c.disconnected[p.device_id] = true
  end
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
  state = "playing"
  return c
end

-- 走子：p.move = {from = {row, col}, to = {row, col}, piece, color, captured, isRiverJump, round}
on_action_MOVE = function(c, p)
  if not role_check(c, p, "MOVE") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local move = p.move
  if move == nil then return c end
  if move.from == nil or move.to == nil then return c end
  if move.from.row == nil or move.from.col == nil then return c end
  if move.to.row == nil or move.to.col == nil then return c end
  if move.color ~= "blue" and move.color ~= "red" then return c end
  -- 服务端只追加；合法性由客户端引擎保证（trust client 简化）。
  -- 服务端权威字段：history 唯一真相。
  table.insert(c.history, move)
  -- 胜负判定由客户端算完后发 WIN（这里不再做服务端引擎判定）。
  return c
end

-- 认输：认输方 = 对手赢
on_action_RESIGN = function(c, p)
  if not role_check(c, p, "RESIGN") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  -- 认输方：top_player（红）认输 → 蓝赢；反之 → 红赢
  local topId = c.top_player_id
  c.winner = (p.device_id == topId) and "blue" or "red"
  state = "ended"
  return c
end

-- 胜利声明：客户端本地算完（进入对方兽穴/全灭对方/对方无子可走）后上报。
on_action_WIN = function(c, p)
  if not role_check(c, p, "WIN") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local winner = p.winner
  if winner ~= "blue" and winner ~= "red" then return c end
  local topId = c.top_player_id
  local isFromTop = (p.device_id == topId)
  -- 防作弊：winner=red 只能由 top 声明；winner=blue 只能由 bottom 声明
  if winner == "red" and not isFromTop then return c end
  if winner == "blue" and isFromTop then return c end
  c.winner = winner
  state = "ended"
  return c
end

on_action_RESET = function(c, p)
  if not role_check(c, p, "RESET") then return c end
  c.history = {}
  c.ready = {}
  c.disconnected = {}
  c.winner = nil
  state = "lobby"
  return c
end

-- 房主主动取消"等待重连"（认对手彻底断线）
-- 等价于一次重置，但语义更清晰——明确"放弃等待"。
-- 与 RESET 的区别：waiting 期间 RESET 也合法，RESET 在 lobby/ended 等
-- 状态下也能用，而 CANCEL_WAIT 只在 waiting 状态生效。
on_action_CANCEL_WAIT = function(c, p)
  if not role_check(c, p, "CANCEL_WAIT") then return c end
  if state ~= "waiting" then return c end
  c.history = {}
  c.ready = {}
  c.disconnected = {}
  c.winner = nil
  state = "lobby"
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_ACK", "on_action_DEAL", "on_action_MOVE",
    "on_action_RESIGN", "on_action_RESET", "on_action_WIN",
    "on_action_CANCEL_WAIT",
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
  on_action_CANCEL_WAIT = on_action_CANCEL_WAIT,
}
''';
