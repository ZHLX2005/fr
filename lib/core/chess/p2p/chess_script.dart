// lib/core/chess/p2p/chess_script.dart
//
// 国际象棋的 net_p2p v3 Lua 状态机脚本（v2：READY 门 + 断连等重连）。
//
// ## 协议要点
//
// · 房主 = 白方（先手）—— 建房者（社交房间号模式：先进入自动成为房主）
// · 加入者 = 黑方
// · 第 3 人进入满员房 → on_join 设 rejected_join → 服务端 409（明确拒绝）
// · state 机：
//     lobby   → 双人就位，等待双方 ACK（"准备"）
//     ready   → 双方已 ACK，等待 host 显式 DEAL（"开始"）
//     playing → 对弈中（MOVE / DRAW_OFFER / UNDO_OFFER / RESIGN / CLAIM_END）
//     ended   → 终局（host 可 RESET 回 lobby）
// · 掉线重连（关键）：
//     · 同一 device_id 在 playing/ready 内 on_join → 清 c.disconnected[id]
//       + 双方都 connected → state 保持 playing（不强制回 lobby）
//     · playing/ready 内 on_leave（p.reason == "disconnect"，host 或 guest）
//       → 一律视为瞬态断线：不销毁房间，标 c.disconnected[id] = true，
//       房间保持 alive 等重连（不清 host_id/guest_id/fen/moves）
//     · playing/ready 内 host 非断线离开（reason != "disconnect"）
//       → force_leave guest + state = "ended"
//       （guest 无 host 同步无法继续对弈；与 jungle 的 waiting 不同 ——
//       chess 是回合制严格依赖 host，host 走 = 必须结束）
//     · lobby 内 on_leave（guest 还没来） → host 离开 → 房间 ended 销毁；
//       guest 离开 → 清 guest 槽（视为"没加入"）
//     · ended 内 on_leave → 保持 ended（winner/moves 留作回顾）
//
// ## 角色权限（action_permissions）
//
//   ACK     = "any"     双方都可在 lobby 阶段点准备
//   DEAL    = "host"    双方都 ACK 后由 host 显式开局
//   MOVE    = "current_player"  轮到谁走谁走
//   RESIGN  = "any"     任何一方任何时候都能投
//   DRAW_*  = "any"     议和流程任意一方发起
//   UNDO_*  = "any"     悔棋流程任意一方发起（回退到"轮请求方走"）
//   CLAIM_END = "non_current_player"  刚走完的一方声明将杀/僵局
//   RESET   = "host"    终局后 host 可重开
//
// ## context 字段（服务端权威状态）
//
//   host_id        : string
//   guest_id       : string | nil
//   players        : {device_id → alias}
//   ready          : {device_id → true}        ACK 状态
//   disconnected   : {device_id → true}        离线玩家（仅 playing/ready 内）
//   fen            : string（FEN 标准字符串，空格分隔 6 字段）
//   moves          : [{uci, by, ts, fen}, ...]（fen = 该手走完后的局面，
//                    UNDO_ACCEPT 回退时恢复 c.fen 的唯一来源）
//   draw_offers    : {device_id → true}
//   undo_offers    : {device_id → true}
//   status         : "playing" | "check" | "checkmate" | "stalemate" | "resigned" | "draw"
//   winner         : string | nil（仅 terminal 时存在）
//   action_permissions : {action → role_rule}
//
// ## 服务端权威策略（无引擎 fence）
//
//   与 v1 一致：服务端不嵌引擎，按"结构 + 归属 + 轮次"校验 fence：
//   1. MOVE 只能由 sideToMove 方发起。
//   2. UCI 必须结构合法：len>=4、from/to ∈ [a-h][1-8]、可选第 5 位 ∈ [qrbn]。
//   3. FEN 必须 6 字段 + 首字段 8 段 + sideToMove 字段 = 当前走子方的对侧。
//   4. MOVE 不携带 status（CLAIM_END 单独声明，且只有"刚走完的一方"）。
//   5. RESIGN 自认输；DRAW_OFFER → DRAW_ACCEPT 显式接受。
//   6. UNDO_OFFER → UNDO_ACCEPT 显式接受后 pop 1~2 手（撤销"请求方
//      最近一手 + 其后所有手"），fen 从 pop 后最后一手的走后快照恢复。
//
// ## 残局开局（v3 initial_fen）
//
//   建房 initial_params 可带 initial_fen（残局快照 FEN）：
//     · on_init 结构校验通过 → c.initial_fen = p.initial_fen，房间从该局面开始
//     · c.initial_side 由 initial_fen 第 2 字段推出（'w'/'b'）
//       —— host 永远执先手方：白先残局 host=白，黑先残局 host=黑
//     · role_check / MOVE 的轮次推导统一走 side_to_move(n)（奇偶 + initial_side）
//     · RESET / UNDO 空棋谱回 initial_fen（残局房间重开仍是残局）
//   不带 initial_fen → initial_side='w' + 标准 FEN，行为与 v2 完全一致。
//
// ## MOVE 请求格式
//   {
//     device_id: <必带>, uci: "e2e4" | "e7e8q",
//     fen: "<6 字段 FEN>", ts: <可选>
//   }
//   MOVE **不**携带 status —— 终局判定走 CLAIM_END（见下）。
//
// ## CLAIM_END 请求格式
//   { device_id, reason: "checkmate" | "stalemate" }
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
  c.ready = {}
  c.disconnected = {}
  -- 残局开局（v3）：建房 initial_params 带 initial_fen 时从残局 FEN 起始。
  -- 结构非法 → fallback 标准开局（is_valid_fen_structure 见下方定义；
  -- Lua 表作用域上移函数声明即可全局可见，on_init 在建房时先于此调用）。
  c.initial_fen = nil
  if type(p.initial_fen) == "string" and is_valid_fen_structure(p.initial_fen) then
    c.initial_fen = p.initial_fen
  end
  -- host_color 选身份（v4）：'w' / 'b' / 'random' / nil → default 'w'
  --   'random' 建时掷筛（relay 假定已 seed；onsite 不再 seed，详见 fen_flip
  --   上方注释）。建时一次决定，不再重摇。
  local requested = "w"
  if type(p.host_color) == "string" then
    if p.host_color == "w" or p.host_color == "b" then
      requested = p.host_color
    elseif p.host_color == "random" then
      requested = (math.random(2) == 1) and "w" or "b"
    end
  end
  -- 原 FEN 的 side（不带 FEN 默认 'w'）。
  local fen_side = "w"
  if c.initial_fen ~= nil then
    local fields = {}
    for f in c.initial_fen:gmatch("%S+") do table.insert(fields, f) end
    if fields[2] == "b" then fen_side = "b" end
  end
  -- 强翻转（v4）：残局 FEN 的先手方与 host_color 不一致 → 整体翻转 FEN，
  -- 让 host 永远执先手方。halfmove 保留（位置属性）。
  if c.initial_fen ~= nil and fen_side ~= requested then
    c.initial_fen = fen_flip(c.initial_fen)
  end
  c.initial_side = requested
  -- 标准开局 fallback 也走镜像（host_color='b' 时黑方在下、先手）。
  if c.initial_fen == nil then
    c.initial_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    if requested == "b" then
      c.initial_fen = fen_flip(c.initial_fen)
    end
  end
  c.fen = c.initial_fen
  c.moves = {}
  c.draw_offers = {}
  c.undo_offers = {}
  c.status = "playing"
  c.action_permissions = {
    ACK        = "any",
    DEAL       = "host",
    MOVE       = "current_player",
    RESIGN     = "any",
    DRAW_OFFER = "any",
    DRAW_ACCEPT = "any",
    DRAW_DECLINE = "any",
    UNDO_OFFER = "any",
    UNDO_ACCEPT = "any",
    UNDO_DECLINE = "any",
    CLAIM_END  = "non_current_player",
    RESET      = "host",
  }
  state = "lobby"
  return c
end

-- 角色权限检查（与 jungle / gomoku / tetris 同模式）
-- 轮次由"先手方 + 手数奇偶"推导（残局 v3：initial_side 支持 host 执黑先走）：
--   side_to_move(n) = n 偶数 → initial_side；奇数 → 对侧
function side_to_move(c, n)
  local first = c.initial_side or "w"
  if n % 2 == 0 then return first end
  if first == "w" then return "b" end
  return "w"
end

function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if c.players[p.device_id] == nil then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    -- host 永远执先手方（白先 host=白；黑先残局 host=黑）：
    -- side == initial_side → 轮先手方（host）；否则轮 guest。
    local side = side_to_move(c, #c.moves)
    if side == (c.initial_side or "w") then return p.device_id == c.host_id end
    return p.device_id == c.guest_id
  end
  if rule == "non_current_player" then
    -- 刚走完的一方（= 声明者本人）= side_to_move(#moves - 1)：
    -- 先手方刚走完 → host 声明；guest 刚走完 → guest 声明。
    local last = side_to_move(c, #c.moves - 1)
    if last == (c.initial_side or "w") then
      return p.device_id == c.host_id
    end
    return p.device_id == c.guest_id
  end
  return false
end

on_join = function(c, p)
  -- 关键修复：先识别"断线重连"（同 device_id）
  -- 同会话进程内的 WS 重连 → device_id 相同 → 复用 player + 取消 disconnected
  if c.players[p.device_id] ~= nil then
    c.disconnected[p.device_id] = nil
    return c
  end

  -- guest 槽已占 → 明确拒绝（rejected_join → 服务端 409 join rejected）。
  if c.guest_id ~= nil then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end

  -- 新玩家加入 lobby：分配 guest 槽
  c.players[p.device_id] = p.alias
  c.guest_id = p.device_id
  c.ready[p.device_id] = nil
  -- 不再自动置 playing（v2 READY 门）：双方到 lobby 后各自 ACK → ready，
  -- host 显式 DEAL 才进 playing。
  return c
end

-- 掉线重连 / 玩家退出：lobby / ready / playing / ended 各语义不同
-- 关键区分（v3）：
--   · playing/ready 内 **任何一方** p.reason == "disconnect"
--     （WS 5s grace 超时后服务端触发）→ 一律视为瞬态断线：
--     只标 c.disconnected[id] = true，房间保持 alive，
--     不清 host_id/guest_id/fen/moves —— 等同一 device_id 重连
--     （on_join 清 disconnected 复用原玩家）。
--   · playing/ready 内 **host** 非断线离开（graceful / kicked / room_evicted）
--     → 真正的 host 退出。chess 是回合制且 host 定义引擎权威局面（fen/moves），
--     guest 独自无法继续对弈 → 销毁房间（force_leave guest + ended），
--     延续 v1"房主离开 = 销毁房间"修复。
--   · playing/ready 内 **guest** 非断线离开 → 保留 player + 标 disconnected，
--     等待 guest 同 device_id 重连（host 单独留在房间也可 RESET / 关房）。
--   · lobby 内 guest 离开 → 清 guest 槽（视为"没加入"）；
--     host 离开 → 空房销毁（end_reason="host_left_lobby"）。
--   · ended 内任何人离开 → 保持 ended（winner/moves 留作回顾）。
on_leave = function(c, p)
  c.ready[p.device_id] = nil
  c.draw_offers[p.device_id] = nil
  c.undo_offers[p.device_id] = nil

  if state == "playing" or state == "ready" then
    if p.reason == "disconnect" then
      -- 断线（WS 5s grace 超时）：host / guest 一律瞬态 —— 房间保持 alive
      -- 等重连，不清槽位 / fen / moves。
      c.disconnected[p.device_id] = true
    elseif p.device_id == c.host_id then
      -- host 显式退出（graceful 等非断线原因）：销毁房间（保留 root
      -- 防服务端 422），踢走在场 guest。
      state = "ended"
      c.status = "ended"
      c.end_reason = "host_left"
      if c.guest_id ~= nil and c.players[c.guest_id] ~= nil then
        c.force_leave = { c.guest_id }
      end
    else
      -- guest 显式退出：保留 player + 标 disconnected，等待同 device_id 重连。
      -- 不清 fen/moves，不设 ended —— 等重连的核心。
      c.disconnected[p.device_id] = true
    end
  elseif state == "lobby" then
    -- lobby 阶段：彻底移除（guest 从未实质加入过；host 离开 = 空房销毁）
    c.players[p.device_id] = nil
    c.disconnected[p.device_id] = nil
    if p.device_id == c.guest_id then
      c.guest_id = nil
    elseif p.device_id == c.host_id then
      -- host 在 lobby 阶段退出（无 guest 在场）→ 房间销毁
      state = "ended"
      c.status = "ended"
      c.end_reason = "host_left_lobby"
    end
  elseif state == "ended" then
    -- 终局后有人离开：保持 ended（winner/moves 留给对局回顾）
    -- players 保留（终局画面能显示对手 alias）
    c.disconnected[p.device_id] = true
  end
  return c
end

-- 准备 ACK：双方都在 lobby 阶段点完准备 → 全部 ready → state = "ready"
on_action_ACK = function(c, p)
  if not role_check(c, p, "ACK") then return c end
  if state == "playing" or state == "ended" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = true
  c.disconnected[p.device_id] = nil
  -- 双方 ACK 全到且仍处 lobby → 升 ready（host 尚未开局）
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

-- 开始 DEAL：host 显式从 ready 推 playing。START 是 DEAL 的别名（向后兼容
-- 旧客户端 / 旧 LobbyEntryPage 上的"开始游戏"按钮）。
on_action_DEAL = function(c, p)
  if not role_check(c, p, "DEAL") then return c end
  if state ~= "ready" then return c end
  if c.guest_id == nil then return c end
  -- "准备"门（防御）：双方 ready 表中都必须为 true 才能开局。
  -- 掉线（on_leave 清 ready）后未重连 ACK 的玩家会让开局被拒 ——
  -- 即"等重连"语义：guest 离线 >5s 后 host 无法绕过准备直接开。
  if c.ready[c.host_id] ~= true or c.ready[c.guest_id] ~= true then
    return c
  end
  state = "playing"
  -- ready 表清空（准备是"本局"的：下一局 RESET 回 lobby 后双方重新 ACK）。
  c.ready = {}
  -- disconnected 不清：仅 on_join 同 device_id 重连时才清（保持"在线"语义清晰）
  return c
end

on_action_START = function(c, p)
  return on_action_DEAL(c, p)
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

-- FEN 整体颜色翻转（v4：host_color 强压倒残局时用）：
--   board:    字符大小写互换 (P↔p, R↔r, N↔n, B↔b, Q↔q, K↔k)，行号反转
--             (rank 1↔8, 2↔7, 3↔6, 4↔5)。数字原样（每行 8 列的语义不变）。
--   side:     'w' ↔ 'b'
--   castling: K↔k, Q↔q 互换（'-' 透传）
--   en passant: 文件不变，行号 1↔8（合法 ep 仅在 3/6 行；3↔6 自然对称）
--   halfmove: 保留（位置属性而非路径属性，翻转后仍是有意义的"自上次兵/吃子以来的半步数"）
--   fullmove: 不变
--
-- 输入结构非法（FEN 不是 6 字段、或 board 不是 8 段）→ 原样返回，不抛错。
function fen_flip(fen)
  if type(fen) ~= "string" then return fen end
  local fields = {}
  for field in fen:gmatch("%S+") do table.insert(fields, field) end
  if #fields ~= 6 then return fen end
  local ranks = {}
  for r in fields[1]:gmatch("[^/]+") do table.insert(ranks, r) end
  if #ranks ~= 8 then return fen end

  local function swap_case(ch)
    if ch:match("%l") then return ch:upper()
    elseif ch:match("%u") then return ch:lower() end
    return ch
  end
  local function flip_rank(rank)
    return rank:gsub(".", swap_case)
  end

  -- board: 行号反转 + 每字符大小写互换
  local reverse_ranks = {}
  for i = 8, 1, -1 do
    reverse_ranks[#reverse_ranks + 1] = flip_rank(ranks[i])
  end
  local new_board = table.concat(reverse_ranks, "/")

  -- side 互换
  local new_side = (fields[2] == "w") and "b" or "w"

  -- castling 大小写互换
  local new_castle = fields[3]:gsub("[KQkq]", swap_case)

  -- en passant：行号 1↔8（仅 3 / 6 是合法 ep 行）
  local new_ep = fields[4]
  if new_ep ~= "-" and #new_ep == 2 then
    local file, row = new_ep:sub(1, 1), new_ep:sub(2, 2)
    if file:match("[a-h]") and row:match("[1-8]") then
      new_ep = file .. tostring(9 - tonumber(row))
    end
  end

  return new_board .. " " .. new_side .. " " .. new_castle
            .. " " .. new_ep .. " " .. fields[5] .. " " .. fields[6]
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
  -- UCI 结构校验（畸形 UCI 直接拒绝）
  if not is_valid_uci(p.uci) then
    return c
  end
  -- FEN 结构校验 + sideToMove 反证：走完后 FEN 的轮走方必须 =
  -- side_to_move(n+1)（残局 v3：由 initial_side + 手数奇偶推导，白先/黑先通用；
  -- 白先时与旧逻辑 (n%2==0)→"b" 完全等价）。
  if not is_valid_fen_structure(p.fen) then
    return c
  end
  local fields = {}
  for field in p.fen:gmatch("%S+") do table.insert(fields, field) end
  local expect_side = side_to_move(c, #c.moves + 1)
  if fields[2] ~= expect_side then
    return c
  end
  -- 记录走法（c.moves 是追加式唯一走法权威；fen = 走后局面快照，
  -- UNDO_ACCEPT 回退时恢复 c.fen 的唯一来源）
  table.insert(c.moves, {
    uci = p.uci,
    by = p.device_id,
    ts = p.ts or 0,
    fen = p.fen,
  })
  -- 客户端负责算新 FEN（dart 引擎）；服务端只做结构校验后落盘。
  -- status 不随 MOVE 更新 —— 终局只能走 CLAIM_END / RESIGN / DRAW_OFFER(+ACCEPT)。
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
  -- 投降方的对手为赢家
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
  -- 双方各自已挂 offer → 直接成和棋
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
--   · 白（host）最后一手在奇数位：n 奇 → pop 1；n 偶 → pop 2
--   · 黑（guest）最后一手在偶数位：n 偶 → pop 1；n 奇 → pop 2
-- fen 恢复：pop 后最后一手的走后快照（MOVE entry 存的 fen）；
-- 空棋谱 → 起始局面。与 DRAW 不同：双方同时挂 undo offer 不自动生效
-- （回退手数取决于请求方角色，必须显式接受）。
-- 权限：不走 role_check —— "any" 之外还需要"对局方 + 手数门"，手写判断
-- 恰是 role_check 无法表达的细粒度校验。
on_action_UNDO_OFFER = function(c, p)
  if state ~= "playing" then
    return c
  end
  if c.status ~= "playing" and c.status ~= "check" then
    return c
  end
  local n = #c.moves
  -- 没走任何一手 → 无从悔棋
  if n == 0 then
    return c
  end
  local is_host = (p.device_id == c.host_id)
  local is_guest = (p.device_id == c.guest_id)
  if not is_host and not is_guest then
    return c
  end
  -- 黑方（guest）一手未走 → 无从悔棋（白 n>=1 已被上面 n==0 门覆盖）
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
  -- 请求方 = 挂 undo offer 的对方；没有 offer → 拒绝
  local requester = nil
  if p.device_id == c.host_id then
    if c.undo_offers[c.guest_id] == true then requester = c.guest_id end
  elseif p.device_id == c.guest_id then
    if c.undo_offers[c.host_id] == true then requester = c.host_id end
  end
  if requester == nil then
    return c
  end
  -- 双方同时挂 offer → 全部作废（回退手数取决于请求方角色，歧义状态
  -- 不回退；清干净让双方从"悔棋"按钮重新发起）。
  if c.undo_offers[p.device_id] == true then
    c.undo_offers = {}
    return c
  end
  -- offer 存续期间 moves 不变（MOVE 会清 undo_offers），
  -- UNDO_OFFER 已校验请求方至少一手 → pop 1~2 手必然合法（> 0 门防御兜底）。
  -- ★ 通用性：先手方（host，白先=白 / 黑先残局=黑）总是走奇数位手
  --   （1,3,5…），后手方走偶数位 —— 黑先残局同样成立，无需按颜色分支。
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
  -- 恢复 fen：pop 后最后一手的走后快照；空棋谱 → initial_fen
  -- （残局 v3：残局房间回残局起点；旧协议 entry 无 fen 的防御分支
  -- —— 实际不可达：脚本随建房下发）
  if #c.moves > 0 and c.moves[#c.moves].fen ~= nil then
    c.fen = c.moves[#c.moves].fen
  else
    c.fen = c.initial_fen or "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  end
  c.undo_offers = {}
  c.draw_offers = {}
  -- 已知限制：回退后局面可能仍是"将军"，但与 MOVE 不算 status 一致
  -- （服务端无引擎），这里复位 playing；下一手 MOVE/CLAIM_END 自然修正。
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

-- 重开（RESET）—— 仅房主可在终局后发起；棋盘/棋谱/状态全部回退到 lobby
-- （v2：RESET 不直接回 playing，要求双方重新 ACK + DEAL）
-- 残局 v3：fen 回 initial_fen（残局房间重开仍是残局；标准房 = 标准开局）
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
