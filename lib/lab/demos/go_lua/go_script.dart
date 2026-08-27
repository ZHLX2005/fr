// lib/lab/demos/go_lua/go_script.dart
//
// 围棋（Go）双人对战 Lua 状态机脚本。
//
// 与五子棋/黑白棋的差异：**服务端权威计算落子结果**。
//   - 每次 MOVE 从 history 重放棋盘 → 校验（占位/自杀/打劫）→ 提子 → 记 ko_spot
//   - 客户端纯渲染，零规则计算（防作弊 + 强一致）
//   - 终局 = 双方连过 → 客户端本地数子 → 双方发 WIN(area) → 服务端比对一致
//
// 规则算法翻译自 orca0613/go-game（MIT，75 行 Python）：
//   get_dead_group（泛洪找无气群）+ handle_move（提子/自杀/ko_spot）。
//
// 坐标约定：Lua 内部全程 1-based（board[row][col], row/col ∈ [1, size]）。
//   客户端 move = {x, y}（0-based）→ on_action_MOVE 入口转 1-based。
//   ko_spot 存回 0-based（客户端期望）。
const String kGoScript = r'''
-- 角色权限检查（与五子棋同模式）
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    -- 当前轮到谁：history 长度（含 pass）为偶数 → 黑；奇数 → 白。
    -- 注意：pass 也消耗一手（占一个 history 槽位），不能"跳 pass 看上一手"，
    -- 否则双方连过无法完成（第二手 pass 会被拒，state 永远进不了 ended）。
    local curIsBlack = (#c.history % 2) == 0
    return (curIsBlack and p.device_id == c.black_player_id)
        or (not curIsBlack and p.device_id ~= c.black_player_id)
  end
  return false
end

-- 越界判定（1-based）
function is_outside(row, col, size)
  return row < 1 or row > size or col < 1 or col > size
end

-- 深拷贝二维棋盘（1-based）
function copy_board(board, size)
  local nb = {}
  for i = 1, size do
    nb[i] = {}
    for j = 1, size do nb[i][j] = board[i][j] end
  end
  return nb
end

-- 泛洪找无气群；有气返回空。board/row/col 均 1-based。
function get_dead_group(board, row, col, color, size)
  if is_outside(row, col, size) then return {} end
  if color == 0 or board[row][col] ~= color then return {} end
  local opponent = (color == 1) and 2 or 1
  local nb = copy_board(board, size)
  local dead = {}
  local stack = { {row, col} }
  while #stack > 0 do
    local cur = table.remove(stack)
    local cy, cx = cur[1], cur[2]
    if not is_outside(cy, cx, size) then
      if nb[cy][cx] == color then
        nb[cy][cx] = opponent  -- 标记已访问
        table.insert(dead, cur)
        table.insert(stack, {cy - 1, cx})
        table.insert(stack, {cy + 1, cx})
        table.insert(stack, {cy, cx - 1})
        table.insert(stack, {cy, cx + 1})
      elseif nb[cy][cx] == opponent then
        -- 已访问或对方棋子，跳过
      else
        return {}  -- 遇到空点 → 有气，不死
      end
    end
  end
  return dead
end

-- 落子 + 提子 + 自杀/打劫判定。
-- 入参：board 1-based；move = {x, y}（0-based）；color 1=黑 2=白；size。
-- 返回：new_board(1-based), ko_spot(0-based 或 nil), killed_count(本次提子数)。
--      自杀/占位/越界返回 nil。
function handle_move(board, move, color, size)
  local row, col = move.y + 1, move.x + 1  -- 0-based → 1-based
  if is_outside(row, col, size) then return nil end
  if board[row][col] ~= 0 then return nil end  -- 占位
  local opponent = (color == 1) and 2 or 1
  local nb = copy_board(board, size)
  nb[row][col] = color
  local killed = {}
  local killed_set = {}
  local function add_killed(group)
    for _, g in ipairs(group) do
      local key = g[1] .. "," .. g[2]
      if not killed_set[key] then
        killed_set[key] = true
        table.insert(killed, g)
      end
    end
  end
  -- 检查 4 邻对方群（同一对方群可能被多个邻点同时扫到，用 killed_set 去重，
  -- 保证 killed_count 是实际被提棋子数，避免 orca0613 Python 版重复计数）
  local neighbors = { {row-1,col}, {row+1,col}, {row,col-1}, {row,col+1} }
  for _, n in ipairs(neighbors) do
    if not is_outside(n[1], n[2], size) and nb[n[1]][n[2]] == opponent then
      add_killed(get_dead_group(nb, n[1], n[2], opponent, size))
    end
  end
  local suicide = get_dead_group(nb, row, col, color, size)
  if #killed == 0 and #suicide > 0 then return nil end  -- 自杀禁止
  local ko_spot = nil
  if #killed == 1 and #suicide == 1 then
    ko_spot = { x = killed[1][2] - 1, y = killed[1][1] - 1 }  -- 转回 0-based
  end
  local killed_count = #killed
  for _, k in ipairs(killed) do nb[k[1]][k[2]] = 0 end  -- 提子
  return nb, ko_spot, killed_count
end

-- 从 history 重放「到上一步为止」的棋盘 + 实算提子数 + ko_spot。
-- 调用时机：on_action_MOVE 里 c.history 尚不含本步，故重放的是历史。
-- 返回 board(1-based), captures({black,white}), ko_spot(0-based 或 nil)。
function replay(c, size)
  local board = {}
  for i = 1, size do
    board[i] = {}
    for j = 1, size do board[i][j] = 0 end
  end
  local captures = { black = 0, white = 0 }
  local ko_spot = nil
  for _, mv in ipairs(c.history) do
    if not mv.pass then
      local color = mv.isBlack and 1 or 2
      local nb, new_ko, killed_count = handle_move(board, mv, color, size)
      if nb ~= nil then
        board = nb
        ko_spot = new_ko
        if color == 1 then
          captures.black = captures.black + killed_count
        else
          captures.white = captures.white + killed_count
        end
      end
    end
  end
  return board, captures, ko_spot
end

on_init = function(c, p)
  c.host_id = p.device_id
  c.black_player_id = p.device_id  -- host = 黑先手
  c.players = {}
  c.players[p.device_id] = p.alias
  c.ready = {}
  c.history = {}
  c.captures = { black = 0, white = 0 }
  c.ko_spot = nil
  c.passes = 0
  c.size = p.size or 9
  c.area_black = nil
  c.area_white = nil
  c.area_black_from = nil
  c.area_white_from = nil
  c.black_reported_black = nil   -- 黑方上报的黑点数
  c.white_reported_black = nil   -- 白方上报的黑点数
  c.action_permissions = {
    ACK    = "any",
    DEAL   = "host",
    MOVE   = "current_player",
    PASS   = "current_player",
    RESIGN = "any",
    WIN    = "any",
    RESET  = "host",
  }
  state = "lobby"
  return c
end

on_join = function(c, p)
  if c.players[p.device_id] ~= nil then return c end
  local count = 0
  for _, _ in pairs(c.players) do count = count + 1 end
  if count >= 2 then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end
  c.players[p.device_id] = p.alias
  c.ready[p.device_id] = nil
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  c.ready[p.device_id] = nil
  return c
end

on_action_ACK = function(c, p)
  if not role_check(c, p, "ACK") then return c end
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
  if not role_check(c, p, "DEAL") then return c end
  if state ~= "ready" then return c end
  state = "playing"
  return c
end

-- 落子：p.move = {x, y, isBlack}（0-based x/y）
on_action_MOVE = function(c, p)
  if not role_check(c, p, "MOVE") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local move = p.move
  if move == nil then return c end
  if move.x == nil or move.y == nil or move.isBlack == nil then return c end
  -- 校验 move.isBlack 必须是当前玩家颜色（history 长度含 pass，偶黑奇白）
  local curIsBlack = (#c.history % 2) == 0
  if move.isBlack ~= curIsBlack then return c end  -- 颜色不符，拒绝

  local color = move.isBlack and 1 or 2
  local board, captures, ko_spot = replay(c, c.size)
  -- 打劫禁止：不得立即回提上一手造成的劫争点（ko_spot 为 0-based）。
  -- 仅当无 pass 间隔时生效（对手 pass 后劫禁解除，c.passes > 0 时放行）。
  if c.passes == 0 and ko_spot ~= nil
      and ko_spot.x == move.x and ko_spot.y == move.y then
    return c
  end
  local nb, new_ko, killed_count = handle_move(board, move, color, c.size)
  if nb == nil then return c end  -- 非法（越界/占位/自杀）

  move.captured = killed_count or 0
  c.captures = captures  -- 到上一步的 captures
  if color == 1 then
    c.captures.black = c.captures.black + killed_count
  else
    c.captures.white = c.captures.white + killed_count
  end
  table.insert(c.history, move)
  c.ko_spot = new_ko
  c.passes = 0
  return c
end

-- 过手
on_action_PASS = function(c, p)
  if not role_check(c, p, "PASS") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  table.insert(c.history, { pass = true })
  c.passes = c.passes + 1
  if c.passes >= 2 then
    state = "ended"  -- 双方连过 → 数子终局（等客户端 WIN）
  end
  return c
end

on_action_RESIGN = function(c, p)
  if not role_check(c, p, "RESIGN") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local blackId = c.black_player_id
  c.winner = (p.device_id == blackId) and "white" or "black"
  state = "ended"
  return c
end

-- 数子终局：客户端连过后本地数子 → 发 WIN(area)。双方对同一色点数一致才终局。
on_action_WIN = function(c, p)
  if not role_check(c, p, "WIN") then return c end
  if c.winner ~= nil then return c end  -- 幂等：winner 已定（认输/已记终局）则忽略后续 WIN
  if state ~= "ended" then return c end
  if c.players[p.device_id] == nil then return c end
  local area = p.area
  if area == nil then return c end
  local ab = area.black
  local aw = area.white
  if ab == nil or aw == nil then return c end
  local blackId = c.black_player_id
  if p.device_id == blackId then
    c.area_black = ab
    c.area_black_from = p.device_id
    c.black_reported_black = ab
  else
    c.area_white = aw
    c.area_white_from = p.device_id
    c.white_reported_black = ab
  end
  -- 双方都已上报且 device_id 不同 → 比对双方对黑点数的判定一致
  if c.area_black_from ~= nil and c.area_white_from ~= nil
      and c.area_black_from ~= c.area_white_from
      and c.black_reported_black ~= nil and c.white_reported_black ~= nil then
    if c.black_reported_black == c.white_reported_black then
      -- 双方一致 → 用黑方上报的完整 area 记终局
      local b = c.area_black
      local w = c.area_white
      c.winner = (b > w) and "black" or ((w > b) and "white" or "draw")
    end
  end
  return c
end

on_action_RESET = function(c, p)
  if not role_check(c, p, "RESET") then return c end
  c.history = {}
  c.ready = {}
  c.winner = nil
  c.captures = { black = 0, white = 0 }
  c.ko_spot = nil
  c.passes = 0
  c.area_black = nil
  c.area_white = nil
  c.area_black_from = nil
  c.area_white_from = nil
  c.black_reported_black = nil
  c.white_reported_black = nil
  state = "lobby"
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_ACK", "on_action_DEAL", "on_action_MOVE",
    "on_action_PASS", "on_action_RESIGN", "on_action_WIN", "on_action_RESET",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_ACK = on_action_ACK,
  on_action_DEAL = on_action_DEAL,
  on_action_MOVE = on_action_MOVE,
  on_action_PASS = on_action_PASS,
  on_action_RESIGN = on_action_RESIGN,
  on_action_WIN = on_action_WIN,
  on_action_RESET = on_action_RESET,
}
''';
