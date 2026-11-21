// lib/core/xiangqi/p2p/script/xiangqi_script_lifecycle.dart
//
// 中国象棋 Lua 脚本 —— 生命周期段（relay v3）。
//
// ## 包含
//
// · 顶层 helper（顶层 `function`，Lua 调用时查找；必须在 on_action_* 之前定义）：
//   - is_valid_xiangqi_fen  （结构校验 `10 段局面 + 轮次`）
//   - is_valid_xiangqi_move （`b0e2` —— 列字母 a-i + 行号 0-9，两段）
//   - side_to_move          （由 c.initial_side + 手数奇偶推）
//   - role_check            （current_player / non_current_player / host）
// · 生命周期 handler：on_init / on_join / on_leave
//
// ## 与国际象棋（chess_script_lifecycle）/ 国际跳棋（draughts_script_lifecycle）的差异
//
// · 颜色用 **红 / 黑**（`host_color` ∈ 'r' / 'b' / 'random'），
//   不是白 / 黑；FEN 轮次位也用 'r' / 'b'。红先（`initial_side` 默认 'r'）。
// · 局面是 **中国象棋 FEN**（10 段 + 轮次 + 两个 '-' 占位 + 两个计数），
//   不是 6 字段国际象棋 FEN，也不是跳棋的 `X:W…:B…`。
// · 着法用 **起终点记号** `b0e2`（列字母 a-i + 行号 0-9），不是 UCI / PDN。
// · 终局只有 **将死 / 困毙** 两种（都是判负），没有「三次重复」和棋。
// · 引擎侧的将军 / 困毙判定全在客户端（服务端不做象棋规则推理）。
//
// ## Lua 作用域与拼接顺序
//
// 此段必须放在 `xiangqi_script_actions.dart` 之前拼接。
// 段末尾必须以 `\n` 结尾（保持 assembler 的 `_functionBlock` regex 块边界）。

const String kXiangqiScriptLifecycle = r'''
-- ════════════════════════════════════════════════════════════════
-- 工具函数（顶层全局，actions 段 handler 通过调用时查找）
-- ════════════════════════════════════════════════════════════════

-- 判断中国象棋 FEN 是否结构合法：`<10 段局面> <轮次> ...`
--   局面段：10 段用 '/' 分隔，每段宽 9（数字 = 连续空格数，字母 = 棋子）
--   轮次段：'r'（红走）/ 'b'（黑走）
-- 结构校验（宽度 / 字符集 / 段数）+ **棋子数量与将帅存在性**校验。
-- ⚠ 数量校验不是可有可无：缺将的畸形局面被当作开局接受 → 客户端引擎立刻
--   判 noGeneral → 终局秒判负（还没走一步就结束）。与客户端
--   isValidXiangqiFen / kXiangqiPieceCountCaps 同表。
function is_valid_xiangqi_fen(fen)
  if type(fen) ~= "string" then return false end
  local parts = {}
  for w in fen:gmatch("%S+") do table.insert(parts, w) end
  if #parts < 2 then return false end
  local turn = parts[2]
  if turn ~= "r" and turn ~= "b" then return false end
  local ranks = {}
  for r in parts[1]:gmatch("[^/]+") do table.insert(ranks, r) end
  if #ranks ~= 10 then return false end
  for i = 1, #ranks do
    local width = 0
    for ch in ranks[i]:gmatch(".") do
      if ch == "0" then return false end
      if ch:match("%d") then
        width = width + tonumber(ch)
      elseif ch:match("[KABNRCPkabnrcp]") then
        width = width + 1
      else
        return false
      end
    end
    if width ~= 9 then return false end
  end
  -- 棋子数量：双方各恰好一个将；士/象/马/车/炮 各 ≤ 2，卒/兵 ≤ 5
  local caps = { K = 1, A = 2, B = 2, N = 2, R = 2, C = 2, P = 5 }
  local counts = {}
  for ch in parts[1]:gmatch(".") do
    if ch:match("[KABNRCPkabnrcp]") then
      -- key 保留原始大小写（红 / 黑分列）
      counts[ch] = (counts[ch] or 0) + 1
    end
  end
  for key, cap in pairs(caps) do
    -- 上下限是**每方**的：大写 = 红、小写 = 黑，必须分别比。
    local upper = counts[key] or 0
    local lower = counts[key:lower()] or 0
    if upper > cap or lower > cap then return false end
  end
  -- 双方各恰好一个将（大小写各一个）
  if (counts["K"] or 0) ~= 1 then return false end
  if (counts["k"] or 0) ~= 1 then return false end
  return true
end

-- 判断走法记号是否结构合法：`b0e2`（列字母 a-i + 行号 0-9，两段共 4 字符）
-- ⚠ 服务端 Lua VM（5.1）不支持「捕获组后接量词」——`(...)*` 形式的
--   pattern 会让 match 恒返回 nil（全拒）。这里用纯字符类 pattern，
--   无捕获组（与 chess is_valid_uci 的逐段思路同源，2026-10-17 e2e 实测定案）。
function is_valid_xiangqi_move(uci)
  if type(uci) ~= "string" then return false end
  if uci:match("^[a-i][0-9][a-i][0-9]$") == nil then return false end
  -- 起点与终点不能相同
  if uci:sub(1, 2) == uci:sub(3, 4) then return false end
  return true
end

-- 轮次由"先手方 + 手数奇偶"推导（红先，除非残局 FEN 指定黑先）。
--   side_to_move(n) = n 偶数 → initial_side；奇数 → 对侧
function side_to_move(c, n)
  local first = c.initial_side or "r"
  if n % 2 == 0 then return first end
  if first == "r" then return "b" end
  return "r"
end

-- ════════════════════════════════════════════════════════════════
-- 揭棋（variant = "jieqi"）开局洗牌
-- ════════════════════════════════════════════════════════════════

-- 生成揭棋开局 FEN（服务端权威洗牌）。
--   · 将 / 帅**明置**原位（col 4 底线）；其余每方 15 子
--     （车马炮士象各 2 + 卒/兵 5）洗乱后暗置己方 15 个起始点。
--   · 产物是**标准字符集** FEN（各棋种数量恰在上限内），现有
--     is_valid_xiangqi_fen 直接放行 —— 校验器零改动。
--   · math.random 与 host_color="random" 同源（relay VM 提供）。
--   · 洗牌放服务端：两端只认 initial_fen，不共享种子（客户端从
--     「从未移动过的起始子」推暗子集合，见客户端 jieqi 模块）。
function jieqi_shuffled_fen()
  -- Fisher-Yates：15 子袋，lower = 黑方小写
  local function bag(lower)
    local letters = { "R","R","N","N","C","C","A","A","B","B","P","P","P","P","P" }
    for i = #letters, 2, -1 do
      local j = math.random(i)
      letters[i], letters[j] = letters[j], letters[i]
    end
    if lower then
      for i = 1, #letters do
        letters[i] = string.lower(letters[i])
      end
    end
    return letters
  end
  local b = bag(true)
  local r = bag(false)
  -- 黑方（FEN 前 3 段）：底线 8 子 + k 在 col4；炮位 row2；卒位 row3
  local black_back  = b[1]..b[2]..b[3]..b[4].."k"..b[5]..b[6]..b[7]..b[8]
  local black_cannon = "1"..b[9].."5"..b[10].."1"
  local black_pawn  = b[11].."1"..b[12].."1"..b[13].."1"..b[14].."1"..b[15]
  -- 红方（FEN 后 3 段）：兵位 row6；炮位 row7；底线 8 子 + K 在 col4
  local red_pawn    = r[11].."1"..r[12].."1"..r[13].."1"..r[14].."1"..r[15]
  local red_cannon  = "1"..r[9].."5"..r[10].."1"
  local red_back    = r[1]..r[2]..r[3]..r[4].."K"..r[5]..r[6]..r[7]..r[8]
  return black_back.."/9/"..black_cannon.."/"..black_pawn
      .."/9/9/"..red_pawn.."/"..red_cannon.."/9/"..red_back
      .." r - - 0 1"
end

-- 角色权限检查（象棋：谁执 host_color、谁是当前走子方）
--   current_player：走子方执 c.host_color → 是不是 host？
--   non_current_player：刚走完的一方（= side_to_move(#moves - 1)）
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if c.players[p.device_id] == nil then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    local side = side_to_move(c, #c.moves)
    local host_side = c.host_color or "r"
    if side == host_side then return p.device_id == c.host_id end
    return p.device_id == c.guest_id
  end
  if rule == "non_current_player" then
    local last = side_to_move(c, #c.moves - 1)
    local host_side = c.host_color or "r"
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

  -- host_color：'r' / 'b' / 'random' / nil → default 'r'（红先）
  c.host_color = "r"
  if type(p.host_color) == "string" then
    if p.host_color == "r" or p.host_color == "b" then
      c.host_color = p.host_color
    elseif p.host_color == "random" then
      c.host_color = (math.random(2) == 1) and "r" or "b"
    end
  end

  -- 残局/自定义开局：结构合法才采纳，否则走标准开局。
  c.initial_fen = nil
  if type(p.initial_fen) == "string" and is_valid_xiangqi_fen(p.initial_fen) then
    c.initial_fen = p.initial_fen
  end

  -- 先手方：红先；残局可由 p.first_mover 显式覆盖。
  c.initial_side = "r"
  if type(p.first_mover) == "string" and (p.first_mover == "r" or p.first_mover == "b") then
    c.initial_side = p.first_mover
  elseif c.initial_fen ~= nil then
    -- FEN 第 2 段首字符即轮次方
    local parts = {}
    for w in c.initial_fen:gmatch("%S+") do table.insert(parts, w) end
    if #parts >= 2 and parts[2] == "b" then c.initial_side = "b" end
  end

  if c.initial_fen == nil then
    c.initial_fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
  end
  -- 玩法变体：nil = 标准对局；"jieqi" = 揭棋（SET_RULES 设置，
  -- RESET 时按变体重洗开局）。
  c.variant = nil
  c.fen = c.initial_fen
  c.moves = {}
  c.draw_offers = {}
  c.undo_offers = {}
  c.status = "playing"
  c.winner = nil
  c.end_reason = nil
  c.endgame_label = nil

  c.action_permissions = {
    ACK          = "any",
    DEAL         = "host",
    SET_RULES    = "host",
    MOVE         = "current_player",
    RESIGN       = "any",
    DRAW_OFFER   = "any",
    DRAW_ACCEPT  = "any",
    DRAW_DECLINE = "any",
    UNDO_OFFER   = "any",
    UNDO_ACCEPT  = "any",
    UNDO_DECLINE = "any",
    CLAIM_END    = "non_current_player",
    RESET        = "host",
  }
  state = "lobby"
  return c
end

-- 同 device_id 重连识别 → 空房回收 → guest 满员拒绝。
on_join = function(c, p)
  -- ① 同 device_id 重进 = 断线重连：清离线标记，原座位原样恢复。
  if c.players[p.device_id] ~= nil then
    c.disconnected[p.device_id] = nil
    return c
  end

  -- ② 空房回收（防「幽灵满员」死锁）：房间处于非对局态（lobby / ended）且房内
  --    已无在线玩家 → 新来者接管为新房主，重置成全新房间。
  --    没有这条：房主在 lobby 离场（房间转 ended）+ 客人随后离场（ended 分支只
  --    标 disconnected）会留下 host_id / guest_id 两个幽灵座位，之后任何人
  --    （含房主本人换设备 / 重装）join 都命中 ③ 的满员拒绝 —— 房间死锁到 TTL。
  --    playing / ready 态不回收：座位留给断线重连（id47 语义）。
  local has_live = false
  for id, _ in pairs(c.players) do
    if c.disconnected[id] ~= true then has_live = true end
  end
  if not has_live and (state == "lobby" or state == "ended") then
    c.host_id = p.device_id
    c.players = {}
    c.players[p.device_id] = p.alias
    c.guest_id = nil
    c.ready = {}
    c.disconnected = {}
    c.host_color = "r"
    c.initial_fen = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR r - - 0 1"
    c.initial_side = "r"
    -- 变体一并清掉：回收后的新房是标准对局（否则会留下「variant=jieqi +
    -- 标准 FEN」的矛盾态，客户端把标准开局全部当暗子渲染）。
    c.variant = nil
    c.endgame_label = nil
    c.fen = c.initial_fen
    c.moves = {}
    c.draw_offers = {}
    c.undo_offers = {}
    c.status = "playing"
    c.winner = nil
    c.end_reason = nil
    c.emojiRing = {}
    c.emojiSeq = 0
    c.lastEmojiAt = {}
    c.chatRing = {}
    c.chatSeq = 0
    c.lastChatAt = {}
    state = "lobby"
    return c
  end

  -- ③ 真满员（还有在线玩家占着 guest 座位）→ 拒绝该设备 join。
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

-- 掉线/退出：playing/ready 内一律视为暂时离线（保留 history，同 id 重连即恢复）。
on_leave = function(c, p)
  c.ready[p.device_id] = nil
  c.draw_offers[p.device_id] = nil
  c.undo_offers[p.device_id] = nil

  if state == "playing" or state == "ready" then
    c.disconnected[p.device_id] = true
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
