// lib/core/xiangqi/p2p/script/xiangqi_script_actions.dart
//
// 中国象棋 Lua 脚本 —— action handler 段（relay v3）。
//
// ## 包含
//
// · 所有 on_action_* handler：
//   ACK / DEAL / SET_RULES / MOVE / CLAIM_END / RESIGN /
//   DRAW_OFFER / DRAW_ACCEPT / DRAW_DECLINE /
//   UNDO_OFFER / UNDO_ACCEPT / UNDO_DECLINE / RESET
// · 导出表 `return { definition = {...}, on_init = on_init, … }`
//   **由 assembler 统一生成放最后**（本段不写 return，见 lua_script_assembler）。
//
// ## 与国际象棋 / 国际跳棋的差异
//
// · MOVE 载荷是 `uci`（`b0e2` 起终点记号）而非 UCI / PDN。
// · 终局只有两种，且**都是判负**：
//   reason = checkmate（被将军且无解） / stalemate（未被将军但无着可走，困毙）。
//   声明方（刚走完的一方）获胜 —— 与跳棋的 noMoves 同构。
// · 无「三次重复」和棋理由（象棋一般比赛不强制）。
// · UNDO 与 chess / draughts 同构（offer → accept/decline）：申请方悔
//   「自己的最后一手」，pop 数量按先手方奇偶推。
//
// ## 段末尾必须以 `\n` 结尾（保持 assembler 的 `_functionBlock` regex 块边界）。

const String kXiangqiScriptActions = r'''
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
    if p.host_color == "r" or p.host_color == "b" then
      c.host_color = p.host_color
    elseif p.host_color == "random" then
      c.host_color = (math.random(2) == 1) and "r" or "b"
    end
  end

  local starting = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"

  if p.clear_endgame == true then
    c.initial_fen = starting
    c.initial_side = "r"
    c.endgame_label = nil
  elseif type(p.initial_fen) == "string" and is_valid_xiangqi_fen(p.initial_fen) then
    c.initial_fen = p.initial_fen
    if type(p.first_mover) == "string" and (p.first_mover == "r" or p.first_mover == "b") then
      c.initial_side = p.first_mover
    else
      local parts = {}
      for w in p.initial_fen:gmatch("%S+") do table.insert(parts, w) end
      if #parts >= 2 and parts[2] == "b" then
        c.initial_side = "b"
      else
        c.initial_side = "r"
      end
    end
    if type(p.endgame_label) == "string" and p.endgame_label ~= "" then
      c.endgame_label = p.endgame_label
    else
      c.endgame_label = "残局"
    end
  elseif type(p.first_mover) == "string" and (p.first_mover == "r" or p.first_mover == "b") then
    c.initial_side = p.first_mover
  end

  c.fen = c.initial_fen or starting
  c.moves = {}
  c.ready = {}
  state = "lobby"
  return c
end

-- 走子（MOVE）—— 仅当前走子方可发；记号结构校验 + FEN 轮次反证；不携带终局。
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
  if not is_valid_xiangqi_move(p.uci) then
    return c
  end
  -- FEN 校验 + 轮次反证：走完后 FEN 轮次位必须 = side_to_move(n+1)
  if not is_valid_xiangqi_fen(p.fen) then
    return c
  end
  local expect_side = side_to_move(c, #c.moves + 1)
  local parts = {}
  for w in p.fen:gmatch("%S+") do table.insert(parts, w) end
  if #parts < 2 then return c end
  local fen_turn = parts[2]
  if fen_turn ~= expect_side then
    return c
  end
  table.insert(c.moves, {
    uci = p.uci,
    by = p.device_id,
    ts = p.ts or 0,
    fen = p.fen,
  })
  c.fen = p.fen
  -- 走子后清掉挂起的议和 / 悔棋请求（对方要重新表态）。
  c.draw_offers = {}
  c.undo_offers = {}
  return c
end

-- 终局声明（CLAIM_END）：刚走完的一方引擎检测到终局后上报。
--   reason = checkmate（被将军且无解） / stalemate（困毙，未被将军但无着可走）
--   两者都是**对方判负** → 声明方（刚走完的一方）胜。
on_action_CLAIM_END = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" then
    return c
  end
  local reason = p.reason
  local is_win = (reason == "checkmate" or reason == "stalemate")
  if not is_win then
    return c
  end
  if not role_check(c, p, "CLAIM_END") then
    return c
  end
  c.end_reason = reason
  c.status = "win"
  c.winner = p.device_id
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

-- 悔棋（UNDO）：申请 → 对方接受/拒绝（与 chess / draughts 同构）。
--   · 申请方悔「自己的最后一手」：先手方奇数手 pop 1 / 偶数手 pop 2；
--     后手方奇数手 pop 2 / 偶数手 pop 1 —— 悔完后轮次必须回到申请方。
--   · 先手方 = host_color == initial_side 的一方（host 未必先手，
--     与 chess v8 / draughts 修复同一坑）。
on_action_UNDO_OFFER = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" then
    return c
  end
  local n = #c.moves
  if n == 0 then
    return c
  end
  local is_host = (p.device_id == c.host_id)
  local is_guest = (p.device_id == c.guest_id)
  if not is_host and not is_guest then
    return c
  end
  local host_is_first = ((c.host_color or "r") == (c.initial_side or "r"))
  local requester_is_first = (is_host == host_is_first)
  if (not requester_is_first) and n < 2 then
    return c
  end
  c.undo_offers[p.device_id] = true
  return c
end

on_action_UNDO_ACCEPT = function(c, p)
  if state ~= "playing" then
    return c
  end
  local requester = nil
  if p.device_id == c.host_id then
    if c.undo_offers[c.guest_id] == true then requester = c.guest_id end
  elseif p.device_id == c.guest_id then
    if c.undo_offers[c.host_id] == true then requester = c.host_id end
  end
  if requester == nil then
    return c
  end
  if c.undo_offers[p.device_id] == true then
    c.undo_offers = {}
    return c
  end
  local n = #c.moves
  -- 先手方判定与 UNDO_OFFER 同源：host_color == initial_side 的一方是先手。
  local host_is_first = ((c.host_color or "r") == (c.initial_side or "r"))
  local requester_is_first = ((requester == c.host_id) == host_is_first)
  local pops
  if requester_is_first then
    pops = (n % 2 == 1) and 1 or 2
  else
    pops = (n % 2 == 1) and 2 or 1
  end
  for i = 1, pops do
    if #c.moves > 0 then
      table.remove(c.moves)
    end
  end
  if #c.moves > 0 and c.moves[#c.moves].fen ~= nil then
    c.fen = c.moves[#c.moves].fen
  else
    c.fen = c.initial_fen or "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
  end
  c.undo_offers = {}
  c.draw_offers = {}
  c.status = "playing"
  c.winner = nil
  return c
end

on_action_UNDO_DECLINE = function(c, p)
  if state ~= "playing" then
    return c
  end
  if p.device_id == c.host_id then
    c.undo_offers[c.guest_id] = nil
  elseif p.device_id == c.guest_id then
    c.undo_offers[c.host_id] = nil
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
  c.fen = c.initial_fen or "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
  c.moves = {}
  c.ready = {}
  c.draw_offers = {}
  c.undo_offers = {}
  c.status = "playing"
  c.winner = nil
  c.end_reason = nil
  -- 清断线标记与 emoji / chat 历史（跨局不泄漏，同 chess / draughts RESET）。
  c.disconnected = {}
  c.emojiRing = {}
  c.emojiSeq = 0
  c.lastEmojiAt = {}
  c.chatRing = {}
  c.chatSeq = 0
  c.lastChatAt = {}
  state = "lobby"
  return c
end
''';
