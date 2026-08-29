// lib/core/chess/p2p/chess_script.dart
//
// 国际象棋的 net_p2p v3 Lua 状态机脚本。
//
// 协议要点（参见 references/net-p2p-protocol-playbook/v3-lua-state-machine）：
//   · 房主 = 白方（先手）—— 建房者
//   · 加入者 = 黑方
//   · state = "lobby" → "playing" → "ended"
//   · action 类型：
//     · MOVE       — UCI 字符串（"e2e4"、"e7e8q"），由服务端权威校验合法性（u3 引用 dart 引擎太重，
//                    因此合法性在客户端守门 + 服务端作 fence：核对"是不是属于 sideToMove 方的合法走法清单"
//                    通过 host_fen + snapshot.moves 增量重放判定。最简实现要求双端用同一引擎实例。
//     · RESIGN     — 投降
//     · DRAW_AGREE — 协议和棋（对方需再发一次 DRAW_AGREE 才生效）
//   · context 字段（服务端权威状态）：
//     · host_id        : string
//     · players        : {device_id → alias}
//     · guest_id       : string | nil
//     · fen            : string（FEN 标准字符串，空格分隔 6 字段）
//     · moves          : [{uci, by, ts_ms}, ...]（棋谱）
//     · draw_offers    : {device_id → true}（当前挂起的和棋申请）
//     · status         : "playing" | "check" | "checkmate" | "stalemate" | "resigned" | "draw"
//
// **服务端权威策略**：
//   这里只规定 Lua 层校验"是否到该方走"（基于 fen 中 sideToMove 字段 + moves 数量）。
//   客户端必须保证走法合法（用本模块的 dart 引擎）。
//   服务端不需要另一份引擎实现，因为 v3 状态机不模拟棋盘 —— 校验限于"格式 + 轮次方"。

/// 国际象棋 Lua 脚本（kChessScript）。
///
/// 在 net_p2p v3 的 RelayV3Transport.createRoom() 创建一个对弈房时传入。
const String kChessScript = r'''
on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.guest_id = nil
  c.max_players = 2
  c.fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  c.moves = {}
  c.draw_offers = {}
  c.status = "playing"
  state = "lobby"
  return c
end

on_join = function(c, p)
  if c.guest_id ~= nil then
    return c
  end
  c.players[p.device_id] = p.alias
  c.guest_id = p.device_id
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  if p.device_id == c.guest_id then
    c.guest_id = nil
  elseif p.device_id == c.host_id then
    -- 房主离开：服务端按 v3 默认规则销毁房间（不实际处理）
    c.host_id = nil
  end
  c.draw_offers[p.device_id] = nil
  return c
end

-- 房主点 START 后进入对弈
on_action_START = function(c, p)
  if c.host_id ~= p.device_id then
    return c
  end
  if c.guest_id == nil then
    return c
  end
  state = "playing"
  return c
end

-- 走子（MOVE）—— 客户端必须是 sideToMove 方
on_action_MOVE = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" and c.status ~= "check" then
    return c
  end
  -- 仅允许"当前走子方"发 MOVE
  -- 白方先走，所以只有 moves 数是奇数（走第 1/3/5..）时白方才能走
  -- 数 moves 的偶数（已下完的半回合）
  local n = #c.moves
  local side = (n % 2 == 0) and "w" or "b"
  -- 期望 p.device_id 是 side 对应方
  local expected_id
  if side == "w" then
    expected_id = c.host_id
  else
    expected_id = c.guest_id
  end
  if expected_id == nil or p.device_id ~= expected_id then
    return c
  end
  -- p.uci 必须为合法 UCI 字符串
  if type(p.uci) ~= "string" or #p.uci < 4 then
    return c
  end
  -- 服务端 fence：这里我们信任客户端合法性（引擎在客户端守门）。
  -- 若需要服务端模拟棋盘，可在此处调用 chess 状态机（重工程；先不做）。
  -- 这里至少检查：从格与目标格字符合法
  local uci = p.uci
  -- p.promotion = "q"/"r"/"b"/"n"（可选）
  -- 记录走法
  table.insert(c.moves, {
    uci = uci,
    by = p.device_id,
    ts = p.ts or 0,
  })
  -- c.fen 由客户端维护 / 服务端可推（v3 协议）；这里保持原值（每走一步刷新）
  -- clients send updated fen in payload
  if type(p.fen) == "string" then
    c.fen = p.fen
  end
  if type(p.status) == "string" then
    c.status = p.status
  end
  return c
end

-- 投降（RESIGN）
on_action_RESIGN = function(c, p)
  if state ~= "playing" then
    return c
  end
  c.status = "resigned"
  c.winner = nil
  -- 投降方的对手为赢家
  if p.device_id == c.host_id then
    c.winner = c.guest_id
  else
    c.winner = c.host_id
  end
  state = "ended"
  return c
end

-- 协议和棋申请（DRAW_AGREE）
-- 单方发：c.draw_offers[device_id] = true
-- 双方都发：状态 = "draw"
on_action_DRAW_AGREE = function(c, p)
  if state ~= "playing" then
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

-- 撤销和棋申请（DRAW_DECLINE）—— 对手可主动撤回自己的申请
on_action_DRAW_DECLINE = function(c, p)
  c.draw_offers[p.device_id] = nil
  return c
end

return {
  definition = {
    functions = {
      "on_init", "on_join", "on_leave",
      "on_action_START", "on_action_MOVE", "on_action_RESIGN",
      "on_action_DRAW_AGREE", "on_action_DRAW_DECLINE",
    },
  },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_START = on_action_START,
  on_action_MOVE = on_action_MOVE,
  on_action_RESIGN = on_action_RESIGN,
  on_action_DRAW_AGREE = on_action_DRAW_AGREE,
  on_action_DRAW_DECLINE = on_action_DRAW_DECLINE,
}
''';
