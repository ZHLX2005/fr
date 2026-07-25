// lib/lab/demos/team_card/quoridor_script.dart
//
// 围追堵截 (Quoridor) 双人对战 Lua 状态机脚本。
// 跟随它的 demo (lib/lab/demos/surround_game_lua/) — Lua 脚本随 demo 走，不放 net_p2p。
//
// 详见 quoridor_script.dart 同目录同名 .md 注释（这里是 demo 自身业务）。

/// 围追堵截 (Quoridor) 双人对战脚本 — kSurroundGameScript
///
/// ## 概述
///
/// 无大厅阶段，房主建房间后直接进入等待，双方都 ACK → 游戏开始。
/// 整个游戏状态仅存 `history`（棋谱数组），客户端从棋谱重建完整 GameState。
///
/// ## 状态机
///
/// ```
///    CreateRoom → state="lobby"     Owner 等 Guest 加入
///    Guest join → state="lobby"     两人生成，等 ACK
///    ACK × 2     → state="ready"   双方 ACK
///    DEAL (host) → state="playing" 游戏开始
///    MOVE        → state不变       追加一步棋谱
///    RESIGN      → state="ended"   认输
/// ```
///
/// ## context 字段
///
///   - `host_id`       : string
///   - `top_player_id` : string  权威服务端字段 = 创建者（host），客户端据此推 imTop
///   - `players`       : {device_id: alias, …}
///   - `history`       : [MoveRecord.toJson, …]  唯一权威状态
///   - `ready`         : {device_id: true, …}
///   - `undo_pending`  : {requester: did} 或 nil
///
/// ## 镜像策略
///
/// 服务端存**规范坐标系 (canonical)**：
/// - 创建者（host = top_player_id）在 y=0，guest 在 y=8
/// - `history` 始终存规范坐标
/// - 客户端显示时：
///   - guest 看到原始棋盘（自己是下方，对方在上方）
///   - host 看到 y 镜像棋盘（自己也是下方，对方在下方）
const String kSurroundGameScript = r'''
on_init = function(c, p)
  c.host_id = p.device_id
  -- 权威约定：host = top player（y=0），guest = bottom player（y=8）。
  -- 客户端用 top_player_id 推导自己的"我是哪一方"（imTop）。
  c.top_player_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.ready = {}
  c.history = {}
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
  c.undo_pending = nil  -- 离开时清掉未决悔棋请求
  return c
end

on_action_ACK = function(c, p)
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
  if c.host_id ~= p.device_id then return c end
  if state ~= "ready" then return c end
  state = "playing"
  return c
end

on_action_MOVE = function(c, p)
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local move = p.move
  if move == nil then return c end
  table.insert(c.history, move)
  return c
end

on_action_RESIGN = function(c, p)
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  -- 认输方 = 对手赢
  local topId = c.top_player_id
  c.winner = (p.device_id == topId) and "bottom" or "top"
  state = "ended"
  return c
end

-- 胜利声明：客户端用本地 QuoridorEngine 判定某方走到终点后发此事件。
-- Lua 本身没有棋盘引擎，无法自行判断胜利，所以由移动方客户端权威上报。
-- 双方客户端都可能发（都从同一份 history 重建 gs），幂等：state 已 ended 时忽略。
-- 校验：只有 playing 态 + winner 与发送方角色一致才接受（防作弊上报）。
on_action_WIN = function(c, p)
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local winner = p.winner
  if winner ~= "top" and winner ~= "bottom" then return c end
  local topId = c.top_player_id
  local isFromTop = (p.device_id == topId)
  -- winner=top 只能由 top 玩家声明；winner=bottom 只能由 bottom 玩家声明
  if winner == "top" and not isFromTop then return c end
  if winner == "bottom" and isFromTop then return c end
  c.winner = winner
  state = "ended"
  return c
end

on_action_RESET = function(c, p)
  if c.host_id ~= p.device_id then return c end
  c.history = {}
  c.ready = {}
  c.undo_pending = nil
  c.winner = nil
  state = "lobby"
  return c
end

-- 悔棋请求：发起方必须是刚下完一步的玩家（canRequestUndo 规则）
-- c.undo_pending = { requester = did } → 等待对方裁决
on_action_UNDO_REQUEST = function(c, p)
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  -- 已有未决请求：忽略新的（避免重叠）
  if c.undo_pending ~= nil then return c end
  -- 历史非空 + 当前不是该玩家的回合（= 该玩家刚下完）
  if #c.history == 0 then return c end
  local last = c.history[#c.history]
  local topId = c.top_player_id
  local lastWasRequester = (last.isTopPlayer and p.device_id == topId)
                          or (not last.isTopPlayer and p.device_id ~= topId)
  if not lastWasRequester then return c end
  c.undo_pending = { requester = p.device_id }
  return c
end

-- 悔棋响应：仅非发起方能响应；接受则 history 弹栈，状态保持 playing
on_action_UNDO_RESPONSE = function(c, p)
  if state ~= "playing" then return c end
  if c.undo_pending == nil then return c end
  local pending = c.undo_pending
  -- 仅对手能响应（不是发起方）
  if p.device_id == pending.requester then return c end
  if c.players[p.device_id] == nil then return c end
  local accepted = p.accepted
  if accepted == true then
    table.remove(c.history, #c.history)
  end
  c.undo_pending = nil
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_ACK", "on_action_DEAL", "on_action_MOVE",
    "on_action_RESIGN", "on_action_RESET", "on_action_WIN",
    "on_action_UNDO_REQUEST", "on_action_UNDO_RESPONSE",
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
  on_action_UNDO_REQUEST = on_action_UNDO_REQUEST,
  on_action_UNDO_RESPONSE = on_action_UNDO_RESPONSE,
}
''';
