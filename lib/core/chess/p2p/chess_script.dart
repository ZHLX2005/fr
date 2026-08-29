// lib/core/chess/p2p/chess_script.dart
//
// 国际象棋的 net_p2p v3 Lua 状态机脚本。
//
// 协议要点（参见 references/net-p2p-protocol-playbook/v3-lua-state-machine）：
//   · 房主 = 白方（先手）—— 建房者（社交房间号模式：先进入自动成为房主）
//   · 加入者 = 黑方
//   · 第 3 人进入满员房 → on_join 设 rejected_join → 服务端 409（明确拒绝）
//   · state = "lobby" → "playing" → "ended"（host 点 RESET → 重新 "playing"）
//   · action 类型：
//     · MOVE       — UCI 字符串（"e2e4"、"e7e8q"）
//     · RESIGN     — 投降
//     · DRAW_AGREE — 协议和棋（对方需再发一次 DRAW_AGREE 才生效）
//     · DRAW_DECLINE — 撤回自己的和棋申请
//     · RESET      — 房主在终局后发起重开
//   · context 字段（服务端权威状态）：
//     · host_id        : string
//     · players        : {device_id → alias}
//     · guest_id       : string | nil
//     · fen            : string（FEN 标准字符串，空格分隔 6 字段）
//     · moves          : [{uci, by, ts_ms}, ...]（棋谱 —— 追加式唯一走法权威）
//     · draw_offers    : {device_id → true}（当前挂起的和棋申请）
//     · status         : "playing" | "check" | "checkmate" | "stalemate" | "resigned" | "draw"
//     · winner         : string | nil（仅 terminal 时存在）
//
// **服务端权威策略（无引擎 fence）**：
//   本脚本不内嵌象棋引擎（gopher-lua 太重），因此无法验证"走法是否规则合法"。
//   权威设计如下（堵住 FEN 造假 / status 造假 / 畸形 UCI 三类漏洞）：
//   1. MOVE 只能由 sideToMove 方发起（moves 奇偶 → 期望 device_id）。
//   2. UCI 必须结构合法：len>=4、from/to 均 ∈ [a-h][1-8]、可选第 5 位为 [qrbn]。
//   3. c.fen 不再无条件信任客户端 —— 要求 6 个空格字段、首字段 8 段 '/'
//      且 sideToMove 字段 = 当前走子方的**对侧**（白走完必须报 'b'）。
//   4. MOVE 不携带 status（客户端不能借走子声明终局）。将杀/僵局由走子方
//      另发 CLAIM_END 声明，且只有"刚走完的一方"能声明（moves 奇偶校验）。
//   5. RESIGN 是唯一"自认输"路径；DRAW_AGREE 双方达成 = draw。
//   这仍允许"端到端作弊"（无服务器引擎的固有上限），但把协议层从
//   "盲存客户端任意字符串"升级为"结构 + 归属 + 轮次严格校验"。
//
// **MOVE 请求格式**（客户端必须携带）：
//   {
//     device_id: <必带>,          — 由 transport 自动注入
//     uci: "e2e4" | "e7e8q",     — 必须
//     fen: "<6 字段 FEN>",        — 必须（结构校验后写入 c.fen）
//     ts: <可选>
//   }
//   MOVE **不**携带 status —— 终局判定走 CLAIM_END（见下）。
//
// **CLAIM_END 请求格式**：
//   {
//     device_id: <必带>,
//     reason: "checkmate" | "stalemate",  — 必须二选一
//   }
//   仅"刚走完的一方"（= 下一手轮到的对侧）可声明；
//   checkmate 时 winner = 声明方本人，stalemate 时 winner = nil。

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
  -- host（建房者）自动 join / 断线重连 → 幂等：不占 guest 槽。
  -- （不判这个会把 host 误记成 guest，走子归属全错）
  if p.device_id == c.host_id then
    c.players[p.device_id] = p.alias
    return c
  end
  -- 已在房间的玩家重复 join（断线重连）→ no-op
  if c.players[p.device_id] ~= nil then
    return c
  end
  -- guest 槽已占 → 明确拒绝（rejected_join → 服务端 409 join rejected），
  -- 第 3 人不再被静默忽略（社交房间号模式：满员要给清晰提示）。
  if c.guest_id ~= nil then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
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

-- 判断 UCI 是否结构合法（len>=4，from/to ∈ [a-h][1-8]，可选第5位 ∈ [qrbn]）
function is_valid_uci(uci)
  if type(uci) ~= "string" then return false end
  if #uci < 4 or #uci > 5 then return false end
  local from = uci:sub(1, 2)
  local to = uci:sub(3, 4)
  if from:match("^[a-h][1-8]$") == nil then return false end
  if to:match("^[a-h][1-8]$") == nil then return false end
  if #uci == 5 and uci:sub(5, 5):match("^[qrbn]$") == nil then return false end
  return true
end

-- 判断 FEN 是否结构合法：6 个空格字段、首字段 8 段 '/'
function is_valid_fen_structure(fen)
  if type(fen) ~= "string" then return false end
  local fields = {}
  for field in fen:gmatch("%S+") do table.insert(fields, field) end
  if #fields ~= 6 then return false end
  local ranks = {}
  for r in fields[1]:gmatch("[^/]+") do table.insert(ranks, r) end
  return #ranks == 8
end

-- 当前走子方（"w"/"b"）+ 期望 device_id（nil = 尚未满员）
function current_move_context(c)
  local n = #c.moves
  local side = (n % 2 == 0) and "w" or "b"
  local expected_id
  if side == "w" then
    expected_id = c.host_id
  else
    expected_id = c.guest_id
  end
  return side, expected_id
end

-- 走子（MOVE）—— 仅当前走子方可发；结构校验 + FEN sideToMove 反证；不携带 status
on_action_MOVE = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" and c.status ~= "check" then
    return c
  end
  local side, expected_id = current_move_context(c)
  if expected_id == nil or p.device_id ~= expected_id then
    return c
  end
  -- UCI 结构校验（畸形 UCI 直接拒绝）
  if not is_valid_uci(p.uci) then
    return c
  end
  -- FEN 结构校验 + sideToMove 反证：白方走完，FEN 必须轮到 'b'
  if not is_valid_fen_structure(p.fen) then
    return c
  end
  local fields = {}
  for field in p.fen:gmatch("%S+") do table.insert(fields, field) end
  local expect_side = (side == "w") and "b" or "w"
  if fields[2] ~= expect_side then
    return c
  end
  -- 记录走法（c.moves 是追加式唯一走法权威）
  table.insert(c.moves, {
    uci = p.uci,
    by = p.device_id,
    ts = p.ts or 0,
  })
  -- 客户端负责算新 FEN（dart 引擎）；服务端只做结构校验后落盘。
  -- status 不随 MOVE 更新 —— 终局只能走 CLAIM_END / RESIGN / DRAW_AGREE。
  c.fen = p.fen
  c.draw_offers = {}
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
  -- 刚走完的一方：moves 为偶数 → 轮到白 → 刚走完的是黑；反之亦然。
  local n = #c.moves
  local mover_id
  if n % 2 == 0 then
    mover_id = c.guest_id
  else
    mover_id = c.host_id
  end
  if mover_id == nil or p.device_id ~= mover_id then
    return c
  end
  if reason == "checkmate" then
    -- 将杀：赢家 = 刚走完的一方（声明者本人）
    c.status = "checkmate"
    c.winner = p.device_id
  else
    -- 僵局：和棋，无赢家
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

-- 重开（RESET）—— 仅房主可在终局后发起；棋盘/棋谱/状态全部回退到新一局
on_action_RESET = function(c, p)
  if c.host_id ~= p.device_id then
    return c
  end
  if state ~= "ended" then
    return c
  end
  c.fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  c.moves = {}
  c.draw_offers = {}
  c.status = "playing"
  c.winner = nil
  state = "playing"
  return c
end

return {
  definition = {
    functions = {
      "on_init", "on_join", "on_leave",
      "on_action_START", "on_action_MOVE", "on_action_CLAIM_END",
      "on_action_RESIGN", "on_action_DRAW_AGREE", "on_action_DRAW_DECLINE",
      "on_action_RESET",
    },
  },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_START = on_action_START,
  on_action_MOVE = on_action_MOVE,
  on_action_CLAIM_END = on_action_CLAIM_END,
  on_action_RESIGN = on_action_RESIGN,
  on_action_DRAW_AGREE = on_action_DRAW_AGREE,
  on_action_DRAW_DECLINE = on_action_DRAW_DECLINE,
  on_action_RESET = on_action_RESET,
}
''';
