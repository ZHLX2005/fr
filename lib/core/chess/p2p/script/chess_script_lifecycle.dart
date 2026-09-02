// lib/core/chess/p2p/chess_script_lifecycle.dart
//
// 国际象棋 Lua 脚本 —— 生命周期段（v5）。
//
// ## 包含
//
// · 顶层 helper（顶层 `function`，Lua 调用时查找；必须在 on_action_* 之前定义）：
//   - is_valid_uci
//   - is_valid_fen_structure
//   - fen_flip（保留备用，本次不调用 —— host_color 与 first_moker 解耦后
//     服务端不再"强翻转"残局 FEN，让 host 可选执子色而不破坏棋规）
//   - side_to_move（基于 c.initial_side 推 first_moker —— 这是棋规本身，不变）
//   - role_check（v5 改用 c.host_color 判断"走子方是不是 host"）
// · 生命周期 handler：on_init / on_join / on_leave
//
// ## 与 v4 的核心变化
//
// v4 把 `c.initial_side = requested`（requested 是 host_color），导致 host 选
// 'b' 时 host 被判先手方（host_color == initial_side），与用户意图（host 执黑后手）
// 冲突。
//
// v5 解耦：
//   c.host_color   = host 执子色（'w' / 'b'）—— 用户决策
//   c.initial_side = FEN 第 2 字段（无 FEN 默认 'w'）—— first_moker，由棋规决定
// 先手方是 host 还是 guest：host_color == initial_side ? host : guest。
//
// 残局 FEN 不再被翻转：host 选 'b' + 黑先残局 → host 执黑、host 是后手方
// （guest 执白且先走）。这才是"host 选后手"的语义。
//
// ## Lua 作用域与拼接顺序
//
// 此段必须放在 `chess_script_actions.dart` 之前拼接。所有顶层全局
// （helpers / on_init / on_join / on_leave）在 actions 段 handler 调用时
// 已可见 —— Lua 全局查找发生在调用时而非定义时。
//
// 段末尾必须以 `\n` 结尾（拼接处保持换行，避免 `_functionBlock` regex
// 块边界漂移）。

const String kChessScriptLifecycle = r'''
-- ════════════════════════════════════════════════════════════════
-- 工具函数（顶层全局，actions 段 handler 通过调用时查找）
-- ════════════════════════════════════════════════════════════════

-- 判断 UCI 是否结构合法（len>=4，from/to ∈ [a-h][1-8]，可选第5位 ∈ [qrbn]）
function is_valid_uci(uci)
  if type(uci) ~= "string" then return false end
  if #uci < 4 or #uci > 5 then return false end
  local from = uci:sub(1, 2)
  local to = uci:sub(3, 4)
  if from:match("^[a-h][1-8]$") == nil then return false end
  if to:match("^[a-h][1-8]$") == nil then return false end
  if #uci == 5 and uci:sub(5, 5):lower():match("^[qrbn]$") == nil then return false end
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

-- FEN 整体颜色翻转（v4 残局强翻转时用过；v5 host_color 与 first_moker 解耦
-- 后**不再调用**，但 helper 保留以备未来扩展）：
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

-- 轮次由"先手方 + 手数奇偶"推导（first_moker 由 c.initial_side 决定，
-- 这是棋规本身 —— 白方永远先走除非残局黑先）：
--   side_to_move(n) = n 偶数 → initial_side；奇数 → 对侧
function side_to_move(c, n)
  local first = c.initial_side or "w"
  if n % 2 == 0 then return first end
  if first == "w" then return "b" end
  return "w"
end

-- 角色权限检查（v5：改用 c.host_color 判"走子方是不是 host"）
--   current_player：n 偶 → 走子方执 c.host_color → 是不是 host？
--                  n 奇 → 走子方执对侧（执非 host_color 方）→ 是不是 guest？
--   non_current_player：刚走完的一方（= side_to_move(#moves - 1)），同 current_player 推导
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if c.players[p.device_id] == nil then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    local side = side_to_move(c, #c.moves)
    local host_side = c.host_color or "w"
    -- 走子方执 host_color → 走 host；执对侧 → 走 guest。
    if side == host_side then return p.device_id == c.host_id end
    return p.device_id == c.guest_id
  end
  if rule == "non_current_player" then
    local last = side_to_move(c, #c.moves - 1)
    local host_side = c.host_color or "w"
    -- 刚走完的一方执 host_color → 刚才是 host 走；执对侧 → 刚才是 guest 走。
    if last == host_side then return p.device_id == c.host_id end
    return p.device_id == c.guest_id
  end
  return false
end

-- ════════════════════════════════════════════════════════════════
-- 生命周期 handler
-- ════════════════════════════════════════════════════════════════

on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.guest_id = nil
  c.max_players = 2
  c.ready = {}
  c.disconnected = {}

  -- host_color：'w' / 'b' / 'random' / nil → default 'w'
  --   v5：host_color 与 first_moker (c.initial_side) 完全解耦；
  --   random 建时掷筛（relay 假定已 seed；on_init 不再 seed 以免污染上游 RNG 状态）。
  c.host_color = "w"
  if type(p.host_color) == "string" then
    if p.host_color == "w" or p.host_color == "b" then
      c.host_color = p.host_color
    elseif p.host_color == "random" then
      c.host_color = (math.random(2) == 1) and "w" or "b"
    end
  end

  -- 残局开局：保留原 FEN（v5 不再"强翻转" —— host_color 与 FEN 独立）。
  -- 结构非法 → nil 走下方标准开局 fallback。
  c.initial_fen = nil
  if type(p.initial_fen) == "string" and is_valid_fen_structure(p.initial_fen) then
    c.initial_fen = p.initial_fen
  end

  -- initial_side = first_moker：白方永远先走是棋规。
  -- v6：用户可显式指定 first_mover（p.first_mover = 'w' / 'b'），
  -- 残局房间被建房者强制覆盖；不指定则从 FEN 第 2 字段推（向后兼容）。
  c.initial_side = "w"
  if c.initial_fen ~= nil then
    if type(p.first_mover) == "string" and (p.first_mover == "w" or p.first_mover == "b") then
      -- 用户强制：服务端信任 client（与 host_color 同模式）
      c.initial_side = p.first_mover
    else
      -- 默认从 FEN 第 2 字段推
      local fields = {}
      for f in c.initial_fen:gmatch("%S+") do table.insert(fields, f) end
      if fields[2] == "b" then c.initial_side = "b" end
    end
  end

  -- 标准开局 fallback（host 选黑后手时仍保持白先；不再镜像）
  if c.initial_fen == nil then
    c.initial_fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
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

-- 同 device_id 重连识别（v2 已修 Bug 1/2）；guest 满员拒绝。
on_join = function(c, p)
  if c.players[p.device_id] ~= nil then
    c.disconnected[p.device_id] = nil
    return c
  end

  if c.guest_id ~= nil then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end

  c.players[p.device_id] = p.alias
  c.guest_id = p.device_id
  c.ready[p.device_id] = nil
  return c
end

-- 掉线重连 / 玩家退出：lobby / ready / playing / ended 各语义不同
-- 关键区分（v3 已修）：
--   · playing/ready 内任何一方 p.reason == "disconnect" → 视为瞬态断线：
--     只标 c.disconnected[id] = true，房间保持 alive。
--   · playing/ready 内 host 非断线离开 → 销毁房间（force_leave guest + ended）。
--   · playing/ready 内 guest 非断线离开 → 保留 player + 标 disconnected，
--     等待 guest 同 device_id 重连。
--   · lobby 内 guest 离开 → 清 guest 槽；host 离开 → 空房销毁。
--   · ended 内任何人离开 → 保持 ended。
on_leave = function(c, p)
  c.ready[p.device_id] = nil
  c.draw_offers[p.device_id] = nil
  c.undo_offers[p.device_id] = nil

  if state == "playing" or state == "ready" then
    if p.reason == "disconnect" then
      c.disconnected[p.device_id] = true
    elseif p.device_id == c.host_id then
      state = "ended"
      c.status = "ended"
      c.end_reason = "host_left"
      if c.guest_id ~= nil and c.players[c.guest_id] ~= nil then
        c.force_leave = { c.guest_id }
      end
    else
      c.disconnected[p.device_id] = true
    end
  elseif state == "lobby" then
    c.players[p.device_id] = nil
    c.disconnected[p.device_id] = nil
    if p.device_id == c.guest_id then
      c.guest_id = nil
    elseif p.device_id == c.host_id then
      state = "ended"
      c.status = "ended"
      c.end_reason = "host_left_lobby"
    end
  elseif state == "ended" then
    c.disconnected[p.device_id] = true
  end
  return c
end
''';
