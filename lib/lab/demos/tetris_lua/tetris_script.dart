// lib/lab/demos/tetris_lua/tetris_script.dart
//
// 俄罗斯方块 双人实时对战 Lua 状态机脚本。
// 跟随它的 demo (lib/lab/demos/tetris_lua/) — Lua 随 demo 走。
//
// 与五子棋/围追堵截（回合制）的本质差异：
//   - 双方各自本地实时玩，不轮流
//   - 服务端只做两件事：① on_init 生成「共享方块序列」② 广播双方实时状态
//   - 无 history / 无 current_player / 无镜像
//
// 状态机：
//   CreateRoom → lobby      房主等对手
//   ACK × 2   → ready       双方准备
//   START(host)→ playing    游戏开始（双方拿到共享序列，各自本地跑）
//   SYNC(any) → 不变        客户端落定后上报自己的 board/score
//   BUST(any) → 不变/ended  一方堆顶 game over 上报最终分；
//                           第一个 BUST 扣 bust_penalty（鼓励撑久）；
//                           双方都 BUST 后比 final_score → ended，高分者赢
//   RESET(host)→ lobby      再来一局（重生成序列）
//
// context：
//   host_id / players / ready / piece_sequence(共享序列) /
//   states{did:{board,score,lines,pieceIndex,alive}} /
//   finished{did:{score,raw,penalty}} / bust_penalty / winner / loser_id /
//   action_permissions

/// 俄罗斯方块双人实时对战脚本 — kTetrisScript
const String kTetrisScript = r'''
-- 角色权限检查（实时游戏无回合概念，只判 host）
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  return false
end

-- 7-bag：1..7 随机排列（Fisher-Yates）。每 7 个一组，保证不连续重复太多次。
function make_bag()
  local t = {1, 2, 3, 4, 5, 6, 7}
  for i = 7, 2, -1 do
    local j = math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- 拼接 bags 组 7-bag，得到一长串方块序列。双方共享同一份。
function gen_sequence(bags)
  local seq = {}
  for _ = 1, bags do
    local bag = make_bag()
    for _, v in ipairs(bag) do
      table.insert(seq, v)
    end
  end
  return seq
end

on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.ready = {}
  -- 共享方块序列：60 组 7-bag = 420 个方块，足够一局长对战。
  -- 双方从 snapshot 拿同一份，本地按 index 取用 → 序列完全一致。
  c.piece_sequence = gen_sequence(60)
  -- 双方各自的实时状态，由各客户端 SYNC 上报。
  c.states = {}
  -- 已 game over 的玩家最终分。双方都 finished 才比总分判胜。
  c.finished = {}
  -- 第一个 BUST（堆顶）扣分：鼓励撑久，但若技巧好、消行多仍可能反超。
  c.bust_penalty = 500
  c.action_permissions = {
    ACK   = "any",
    START = "host",
    SYNC  = "any",
    BUST  = "any",
    RESET = "host",
  }
  state = "lobby"
  return c
end

on_join = function(c, p)
  c.players[p.device_id] = p.alias
  c.ready[p.device_id] = nil
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  c.ready[p.device_id] = nil
  c.states[p.device_id] = nil
  c.finished[p.device_id] = nil
  return c
end

on_action_ACK = function(c, p)
  if not role_check(c, p, "ACK") then return c end
  if state == "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = true
  local count = 0
  for _ in pairs(c.players) do count = count + 1 end
  local aready = 0
  for _, v in pairs(c.ready) do if v then aready = aready + 1 end end
  if count >= 2 and aready >= count and state == "lobby" then
    state = "ready"
  end
  return c
end

on_action_START = function(c, p)
  if not role_check(c, p, "START") then return c end
  if state ~= "ready" then return c end
  state = "playing"
  return c
end

-- 实时同步：p.state = {board, score, lines, pieceIndex, alive}
-- 客户端每次方块落定后上报自己的堆积状态，对方据此渲染滞后预览。
on_action_SYNC = function(c, p)
  if not role_check(c, p, "SYNC") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  if c.finished[p.device_id] ~= nil then return c end  -- 已 BUST 不再同步
  local s = p.state
  if s == nil then return c end
  c.states[p.device_id] = {
    board = s.board or {},
    score = s.score or 0,
    lines = s.lines or 0,
    pieceIndex = s.pieceIndex or 0,
    alive = s.alive,
  }
  return c
end

-- 一方堆顶 game over 上报最终分（p.score）。
-- 第一个 BUST 扣 bust_penalty（鼓励撑久）；双方都 BUST 后比 final_score，
-- 高分者赢 → ended。这样"先 GG 但消行多技巧好"的人仍可能反超。
on_action_BUST = function(c, p)
  if not role_check(c, p, "BUST") then return c end
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  if c.finished[p.device_id] ~= nil then return c end  -- 幂等
  local raw = tonumber(p.score or 0) or 0
  local done = 0
  for _ in pairs(c.finished) do done = done + 1 end
  local penalty = 0
  if done == 0 then penalty = c.bust_penalty or 500 end
  c.finished[p.device_id] = { score = raw - penalty, raw = raw, penalty = penalty }
  -- 标记该方 states.alive=false，让对方面板显示 GG
  if c.states[p.device_id] ~= nil then c.states[p.device_id].alive = false end
  c.loser_id = p.device_id  -- 先完成（首个 BUST）的人，语义上是本局"先 GG"
  -- 双方都完成 → 比分
  local total = 0
  for _ in pairs(c.players) do total = total + 1 end
  local ndone = 0
  for _ in pairs(c.finished) do ndone = ndone + 1 end
  if total >= 2 and ndone >= total then
    local best_id, best_score = nil, nil
    for did, info in pairs(c.finished) do
      if best_score == nil or info.score > best_score then
        best_id = did
        best_score = info.score
      end
    end
    c.winner = best_id
    state = "ended"
  end
  return c
end

on_action_RESET = function(c, p)
  if not role_check(c, p, "RESET") then return c end
  c.piece_sequence = gen_sequence(60)
  c.states = {}
  c.finished = {}
  c.ready = {}
  c.winner = nil
  c.loser_id = nil
  state = "lobby"
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_ACK", "on_action_START", "on_action_SYNC",
    "on_action_BUST", "on_action_RESET",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_ACK = on_action_ACK,
  on_action_START = on_action_START,
  on_action_SYNC = on_action_SYNC,
  on_action_BUST = on_action_BUST,
  on_action_RESET = on_action_RESET,
}
''';
