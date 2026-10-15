// lib/core/draughts/p2p/script/draughts_script_actions.dart
//
// 国际跳棋 Lua 脚本 —— action handler 段（relay v3）。
//
// ## 包含
//
// · 所有 on_action_* handler：
//   ACK / DEAL / SET_RULES / MOVE / CLAIM_END / RESIGN /
//   DRAW_OFFER / DRAW_ACCEPT / DRAW_DECLINE / RESET
// · 导出表 `return { definition = {...}, on_init = on_init, … }`
//   **由 assembler 统一生成放最后**（本段不写 return，见 lua_script_assembler）。
//
// ## 与国际象棋的差异
//
// · MOVE 载荷是 `pdn`（`32-28` / `32x23x14`）而非 `uci`。
// · 无 check / checkmate / stalemate 三态：跳棋是"无子 / 无着法"直接判负。
// · CLAIM_END 的 reason 取值：noPieces / noMoves（胜）与
//   threefold / kingVsKing（和）。
// · 无 UNDO（跳棋吃子链撤销语义复杂，本期不做）。
//
// ## 段末尾必须以 `\n` 结尾（保持 assembler 的 `_functionBlock` regex 块边界）。

const String kDraughtsScriptActions = r'''
-- 准备 ACK：双方都在 lobby 阶段点完准备 → 全部 ready → state = "ready"
on_action_ACK = function(c, p)
  if not role_check(c, p, "ACK") then return c end
  if state == "playing" or state == "ended" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = true
  c.disconnected[p.device_id] = nil
  local all_ready = true
  local count = 0
  for id, _ in pairs(c.players) do
    count = count + 1
    if c.ready[id] ~= true then all_ready = false end
  end
  if count >= c.max_players and all_ready and state == "lobby" then
    state = "ready"
  end
  return c
end

-- 开始 DEAL：host 显式从 ready 推 playing。START 是 DEAL 的别名。
on_action_DEAL = function(c, p)
  if not role_check(c, p, "DEAL") then return c end
  if state ~= "ready" then return c end
  if c.guest_id == nil then return c end
  if c.ready[c.host_id] ~= true or c.ready[c.guest_id] ~= true then
    return c
  end
  state = "playing"
  c.ready = {}
  return c
end

on_action_START = function(c, p)
  return on_action_DEAL(c, p)
end

-- 准备阶段改规则（SET_RULES）—— 仅 host，仅 lobby/ready。改完清 ready、回 lobby。
on_action_SET_RULES = function(c, p)
  if not role_check(c, p, "SET_RULES") then return c end
  if state ~= "lobby" and state ~= "ready" then return c end

  if type(p.host_color) == "string" then
    if p.host_color == "w" or p.host_color == "b" then
      c.host_color = p.host_color
    elseif p.host_color == "random" then
      c.host_color = (math.random(2) == 1) and "w" or "b"
    end
  end

  local starting = "W:W31-50:B1-20"

  if p.clear_endgame == true then
    c.initial_fen = starting
    c.initial_side = "w"
    c.endgame_label = nil
  elseif type(p.initial_fen) == "string" and is_valid_draughts_fen(p.initial_fen) then
    c.initial_fen = p.initial_fen
    if type(p.first_mover) == "string" and (p.first_mover == "w" or p.first_mover == "b") then
      c.initial_side = p.first_mover
    else
      c.initial_side = (p.initial_fen:sub(1, 1) == "B") and "b" or "w"
    end
    if type(p.endgame_label) == "string" and p.endgame_label ~= "" then
      c.endgame_label = p.endgame_label
    else
      c.endgame_label = "残局"
    end
  elseif type(p.first_mover) == "string" and (p.first_mover == "w" or p.first_mover == "b") then
    c.initial_side = p.first_mover
  end

  c.fen = c.initial_fen or starting
  c.moves = {}
  c.ready = {}
  state = "lobby"
  return c
end

-- 走子（MOVE）—— 仅当前走子方可发；PDN 结构校验 + FEN 轮次反证；不携带终局。
on_action_MOVE = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" then
    return c
  end
  if not role_check(c, p, "MOVE") then
    return c
  end
  if not is_valid_pdn_move(p.pdn) then
    return c
  end
  -- FEN 校验 + 轮次反证：走完后 FEN 首字符必须 = side_to_move(n+1)
  if not is_valid_draughts_fen(p.fen) then
    return c
  end
  local expect_side = side_to_move(c, #c.moves + 1)
  local fen_turn = (p.fen:sub(1, 1) == "B") and "b" or "w"
  if fen_turn ~= expect_side then
    return c
  end
  local captures = 0
  for _ in p.pdn:gmatch("x") do captures = captures + 1 end
  table.insert(c.moves, {
    pdn = p.pdn,
    by = p.device_id,
    ts = p.ts or 0,
    fen = p.fen,
  })
  c.fen = p.fen
  if captures > 0 then
    c.ply_since_capture = 0
  else
    c.ply_since_capture = (c.ply_since_capture or 0) + 1
  end
  c.draw_offers = {}
  return c
end

-- 终局声明（CLAIM_END）：刚走完的一方引擎检测到终局后上报。
--   reason = noPieces / noMoves → 声明方胜
--   reason = threefold / kingVsKing / kingMoveLimit → 和
on_action_CLAIM_END = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" then
    return c
  end
  local reason = p.reason
  local is_win = (reason == "noPieces" or reason == "noMoves")
  local is_draw = (reason == "threefold" or reason == "kingVsKing"
                   or reason == "kingMoveLimit")
  if not is_win and not is_draw then
    return c
  end
  if not role_check(c, p, "CLAIM_END") then
    return c
  end
  c.end_reason = reason
  if is_win then
    c.status = "win"
    c.winner = p.device_id
  else
    c.status = "draw"
    c.winner = nil
  end
  state = "ended"
  return c
end

-- 投降（RESIGN）
on_action_RESIGN = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.players[p.device_id] == nil then
    return c
  end
  c.status = "resigned"
  c.end_reason = "resign"
  if p.device_id == c.host_id then
    c.winner = c.guest_id
  else
    c.winner = c.host_id
  end
  state = "ended"
  return c
end

-- 协议和棋：申请 → 对方接受/拒绝
on_action_DRAW_OFFER = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" then
    return c
  end
  c.draw_offers[p.device_id] = true
  local h = c.draw_offers[c.host_id] == true
  local g = c.draw_offers[c.guest_id] == true
  if h and g and c.guest_id ~= nil then
    c.status = "draw"
    c.end_reason = "agreement"
    c.winner = nil
    state = "ended"
  end
  return c
end

on_action_DRAW_ACCEPT = function(c, p)
  if state ~= "playing" then
    return c
  end
  local opponent_offered = false
  if p.device_id == c.host_id then
    opponent_offered = c.draw_offers[c.guest_id] == true
  elseif p.device_id == c.guest_id then
    opponent_offered = c.draw_offers[c.host_id] == true
  end
  if not opponent_offered then
    return c
  end
  c.status = "draw"
  c.end_reason = "agreement"
  c.winner = nil
  state = "ended"
  return c
end

on_action_DRAW_DECLINE = function(c, p)
  if state ~= "playing" then
    return c
  end
  if p.device_id == c.host_id then
    c.draw_offers[c.guest_id] = nil
  elseif p.device_id == c.guest_id then
    c.draw_offers[c.host_id] = nil
  end
  return c
end

-- 重开（RESET）—— 仅 host，仅终局后。清 history 回 lobby，双方重新准备。
on_action_RESET = function(c, p)
  if not role_check(c, p, "RESET") then
    return c
  end
  if state ~= "ended" then
    return c
  end
  c.fen = c.initial_fen or "W:W31-50:B1-20"
  c.moves = {}
  c.ready = {}
  c.draw_offers = {}
  c.status = "playing"
  c.winner = nil
  c.end_reason = nil
  c.ply_since_capture = 0
  state = "lobby"
  return c
end
''';
