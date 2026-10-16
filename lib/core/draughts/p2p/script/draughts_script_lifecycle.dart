// lib/core/draughts/p2p/script/draughts_script_lifecycle.dart
//
// 国际跳棋 Lua 脚本 —— 生命周期段（relay v3）。
//
// ## 包含
//
// · 顶层 helper（顶层 `function`，Lua 调用时查找；必须在 on_action_* 之前定义）：
//   - is_valid_draughts_fen  （结构校验 `X:W…:B…`）
//   - is_valid_pdn_move      （`32-28` / `32x23x14`）
//   - side_to_move           （由 c.initial_side + 手数奇偶推）
//   - role_check             （current_player / non_current_player / host）
// · 生命周期 handler：on_init / on_join / on_leave
//
// ## 与国际象棋（chess_script_lifecycle）的差异
//
// · FEN 是跳棋格式 `W:W31-50:B1-20`（不是 6 字段棋 FEN）→ 校验与默认值不同。
// · 无易位 / 无吃过路兵 / 无将军 → 无 fen_flip、无 check 状态。
// · 着法用 PDN（`32-28` / `32x23`）而非 UCI。
// · 白方永远先手（FMJD 规则）；c.host_color 仅决定 host 执哪色。
// · 终局：无子 / 无着法 / 三重复 / 王对王。
//
// ## Lua 作用域与拼接顺序
//
// 此段必须放在 `draughts_script_actions.dart` 之前拼接。
// 段末尾必须以 `\n` 结尾（保持 assembler 的 `_functionBlock` regex 块边界）。

const String kDraughtsScriptLifecycle = r'''
-- ════════════════════════════════════════════════════════════════
-- 工具函数（顶层全局，actions 段 handler 通过调用时查找）
-- ════════════════════════════════════════════════════════════════

-- 判断跳棋 FEN 是否结构合法：`X:W…:B…`（X ∈ {W,B}）
-- 完整字符集校验从简：轮次 1 字符 + 两段各有颜色首字母 + 方格记号。
function is_valid_draughts_fen(fen)
  if type(fen) ~= "string" then return false end
  if fen:match("^[WB]:[WB][KMkm0-9,%-\n]*:[WB][KMkm0-9,%-\n]*$") == nil then
    return false
  end
  return true
end

-- 判断 PDN 着法是否结构合法：`32-28` 或 `32x23x14`（方格号 1..50）
-- ⚠ 服务端 Lua VM（5.1）不支持「捕获组后接量词」——`(...)*` 形式的
--   pattern 会让 match 恒返回 nil（全拒）。禁用该写法，改分段校验
--   （同 chess is_valid_uci 的逐段思路，2026-10-17 e2e 实测定案）。
function is_valid_pdn_move(pdn)
  if type(pdn) ~= "string" then return false end
  if pdn == "" then return false end
  -- 分隔符归一后分段检查：只允许 数字;x-;数字[;数字]...
  local cleaned = pdn:gsub("[x%-]", ";")
  if cleaned:match("[^%d;]") ~= nil then return false end
  if cleaned:match("^;") ~= nil or cleaned:match(";$") ~= nil then return false end
  if cleaned:match(";") == nil then return false end
  if cleaned:match(";;") ~= nil then return false end
  for num in cleaned:gmatch("%d+") do
    local n = tonumber(num)
    if n == nil or n < 1 or n > 50 then return false end
  end
  return true
end

-- 轮次由"先手方 + 手数奇偶"推导（白方永远先手，除非残局 FEN 指定黑先）。
--   side_to_move(n) = n 偶数 → initial_side；奇数 → 对侧
function side_to_move(c, n)
  local first = c.initial_side or "w"
  if n % 2 == 0 then return first end
  if first == "w" then return "b" end
  return "w"
end

-- 角色权限检查（跳棋：谁执 host_color、谁是当前走子方）
--   current_player：走子方执 c.host_color → 是不是 host？
--   non_current_player：刚走完的一方（= side_to_move(#moves - 1)）
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if c.players[p.device_id] == nil then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    local side = side_to_move(c, #c.moves)
    local host_side = c.host_color or "w"
    if side == host_side then return p.device_id == c.host_id end
    return p.device_id == c.guest_id
  end
  if rule == "non_current_player" then
    local last = side_to_move(c, #c.moves - 1)
    local host_side = c.host_color or "w"
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
  c.host_color = "w"
  if type(p.host_color) == "string" then
    if p.host_color == "w" or p.host_color == "b" then
      c.host_color = p.host_color
    elseif p.host_color == "random" then
      c.host_color = (math.random(2) == 1) and "w" or "b"
    end
  end

  -- 残局/自定义开局：结构合法才采纳，否则走标准开局。
  c.initial_fen = nil
  if type(p.initial_fen) == "string" and is_valid_draughts_fen(p.initial_fen) then
    c.initial_fen = p.initial_fen
  end

  -- 先手方：白方永远先手（FMJD）；残局可由 p.first_mover 显式覆盖。
  c.initial_side = "w"
  if type(p.first_mover) == "string" and (p.first_mover == "w" or p.first_mover == "b") then
    c.initial_side = p.first_mover
  elseif c.initial_fen ~= nil then
    -- FEN 首字符即轮次方
    if c.initial_fen:sub(1, 1) == "B" then c.initial_side = "b" end
  end

  if c.initial_fen == nil then
    c.initial_fen = "W:W31-50:B1-20"
  end
  c.fen = c.initial_fen
  c.moves = {}
  c.draw_offers = {}
  c.status = "playing"
  c.winner = nil
  c.ply_since_capture = 0
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
    CLAIM_END    = "non_current_player",
    RESET        = "host",
  }
  state = "lobby"
  return c
end

-- 同 device_id 重连识别；guest 满员拒绝。
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

-- 掉线/退出：playing/ready 内一律视为暂时离线（保留 history，同 id 重连即恢复）。
on_leave = function(c, p)
  c.ready[p.device_id] = nil
  c.draw_offers[p.device_id] = nil

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
