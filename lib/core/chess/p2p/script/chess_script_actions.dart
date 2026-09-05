// lib/core/chess/p2p/chess_script_actions.dart
//
// 国际象棋 Lua 脚本 —— action handler 段（v5）。
//
// ## 包含
//
// · 所有 on_action_* handler：ACK / DEAL / START / MOVE / CLAIM_END /
//   RESIGN / DRAW_OFFER / DRAW_ACCEPT / DRAW_DECLINE /
//   UNDO_OFFER / UNDO_ACCEPT / UNDO_DECLINE / RESET
// · 导出表 `return { definition = {...}, on_init = on_init, ... }` ——
//   **必须放最后一段**，因为导出表引用的全局（on_init/on_join/on_leave/所有
//   on_action_*）必须在导出时已定义。
//
// ## 与 v4 的核心变化
//
// v4 把 host_color 与 c.initial_side 合并，导致 host 选 'b' 时 role_check
// 误判 host 为先手方。v5 解耦后 action 段**算法逻辑不变**（仍按
// side_to_move(n) 推 first_moker），只是注释更新（host 是先手方还是后手方
// 由 c.host_color 决定，不再由 c.initial_side 直接等同 host）。
//
// UNDO_ACCEPT 计算逻辑：requester == host_id 仍是"先手方最近一手"的判据；
// 因为 host 是 first_moker 当且仅当 host_color == initial_side，新算法与
// 旧算法的"白先 / 黑先残局"等价情况都保持一致。
//
// ## Lua 作用域与拼接顺序
//
// 此段必须放在 `chess_script_lifecycle.dart` 之后、`chess_script.dart`
// 入口拼接的最后。导出表 `return {...}` 必须绝对最后。
//
// 段末尾必须以 `\n` 结尾（保持 `_functionBlock` regex 块边界）。

const String kChessScriptActions = r'''
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

-- 开始 DEAL：host 显式从 ready 推 playing。START 是 DEAL 的别名（向后兼容）。
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

-- 走子（MOVE）—— 仅当前走子方可发；结构校验 + FEN sideToMove 反证；不携带 status
on_action_MOVE = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" and c.status ~= "check" then
    return c
  end
  if not role_check(c, p, "MOVE") then
    return c
  end
  if not is_valid_uci(p.uci) then
    return c
  end
  -- FEN 结构校验 + sideToMove 反证：走完后 FEN 的轮走方必须 =
  -- side_to_move(n+1)。first_moker 由 c.initial_side 推（棋规本身）。
  if not is_valid_fen_structure(p.fen) then
    return c
  end
  local fields = {}
  for field in p.fen:gmatch("%S+") do table.insert(fields, field) end
  local expect_side = side_to_move(c, #c.moves + 1)
  if fields[2] ~= expect_side then
    return c
  end
  table.insert(c.moves, {
    uci = p.uci,
    by = p.device_id,
    ts = p.ts or 0,
    fen = p.fen,
  })
  c.fen = p.fen
  c.draw_offers = {}
  c.undo_offers = {}
  return c
end

-- 终局声明（CLAIM_END）：走子方引擎检测到 checkmate / stalemate 后上报。
-- 只有"刚走完的一方"（= 下一手轮到的对侧）能声明；幂等。
on_action_CLAIM_END = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" and c.status ~= "check" then
    return c
  end
  local reason = p.reason
  if reason ~= "checkmate" and reason ~= "stalemate" then
    return c
  end
  if not role_check(c, p, "CLAIM_END") then
    return c
  end
  if reason == "checkmate" then
    c.status = "checkmate"
    c.winner = p.device_id
  else
    c.status = "stalemate"
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
  c.status = "resigned"
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
  if c.status ~= "playing" and c.status ~= "check" then
    return c
  end
  c.draw_offers[p.device_id] = true
  local h = c.draw_offers[c.host_id] == true
  local g = c.draw_offers[c.guest_id] == true
  if h and g and c.guest_id ~= nil then
    c.status = "draw"
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

-- 协商悔棋（v3）：申请 → 对方接受/拒绝。
-- 语义：撤销"请求方最近一手 + 其后所有手"，回到轮请求方走。
--   · 先手方（host_color == initial_side 时 host 即先手方；否则 guest 是先手方）
--     最后一手在奇数位：n 奇 → pop 1；n 偶 → pop 2
--   · 后手方最后一手在偶数位：n 偶 → pop 1；n 奇 → pop 2
-- 计算逻辑：requester == c.host_id 仍是"先手方最近一手"的判据
-- （v5 与 v4 算法等价 —— 因为 host 是 first_moker 当且仅当 host_color == initial_side）。
-- 与 DRAW 不同：双方同时挂 undo offer 不自动生效，必须显式接受。
on_action_UNDO_OFFER = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" and c.status ~= "check" then
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
  if is_guest and n < 2 then
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
  local requester_is_first = (requester == c.host_id)
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
    c.fen = c.initial_fen or "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
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

-- 重开（RESET）—— 仅房主可在终局后发起；fen 回 initial_fen。
on_action_RESET = function(c, p)
  if not role_check(c, p, "RESET") then return c end
  if state ~= "ended" then
    return c
  end
  c.fen = c.initial_fen or "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  c.moves = {}
  c.draw_offers = {}
  c.undo_offers = {}
  c.ready = {}
  c.disconnected = {}
  c.status = "playing"
  c.winner = nil
  state = "lobby"
  -- 清 emoji / chat 历史（跨局不泄漏）
  c.emojiRing = {}
  c.emojiSeq = 0
  c.lastEmojiAt = {}
  c.chatRing = {}
  c.chatSeq = 0
  c.lastChatAt = {}
  return c
end

return {
  definition = {
    functions = {
      "on_init", "on_join", "on_leave",
      "on_action_ACK", "on_action_DEAL", "on_action_START",
      "on_action_MOVE", "on_action_CLAIM_END",
      "on_action_RESIGN", "on_action_DRAW_OFFER", "on_action_DRAW_ACCEPT",
      "on_action_DRAW_DECLINE", "on_action_UNDO_OFFER",
      "on_action_UNDO_ACCEPT", "on_action_UNDO_DECLINE", "on_action_RESET",
    },
  },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_ACK = on_action_ACK,
  on_action_DEAL = on_action_DEAL,
  on_action_START = on_action_START,
  on_action_MOVE = on_action_MOVE,
  on_action_CLAIM_END = on_action_CLAIM_END,
  on_action_RESIGN = on_action_RESIGN,
  on_action_DRAW_OFFER = on_action_DRAW_OFFER,
  on_action_DRAW_ACCEPT = on_action_DRAW_ACCEPT,
  on_action_DRAW_DECLINE = on_action_DRAW_DECLINE,
  on_action_UNDO_OFFER = on_action_UNDO_OFFER,
  on_action_UNDO_ACCEPT = on_action_UNDO_ACCEPT,
  on_action_UNDO_DECLINE = on_action_UNDO_DECLINE,
  on_action_RESET = on_action_RESET,
}
''';
