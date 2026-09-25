// lib/core/sudoku/p2p/script/sudoku_script_actions.dart
//
// kSudokuScript 的 actions 段：SET_PUZZLE / ACK / START / PROGRESS / SUBMIT。
//
// 与 chess/go 一致的服务端契约（v2 修复）：
//   · handler 签名 `(c, p)`，身份字段 `p.device_id`（客户端 applyAction
//     自动注入的是 device_id，不是 uid —— v1 读 payload.uid 永远为 nil）；
//   · 状态机走全局 `state`（lobby → ready → playing → ended）；
//   · 拒绝 = 原样 `return c`（不返回 {ok=...}，避免服务端把返回值当新 context）。
//
// 所有 handler 写在导出表（由 assembler 末尾生成）。
//
// 命名约定：`on_action_SET_PUZZLE = function(...)`（assembler 仅识别
// `on_action_X = function(...)` 模式 —— 见 lua_script_assembler.dart
// `_collectActionNames` 正则）。

const String kSudokuScriptActions = r'''
on_action_SET_PUZZLE = function(c, p)
  -- 仅 host 可调
  if p.device_id ~= c.host_id then return c end
  if state ~= "lobby" and state ~= "ready" then return c end
  local pz = p.puzzle
  local so = p.solution
  if type(pz) ~= 'table' or #pz ~= 81 then return c end
  if type(so) ~= 'table' or #so ~= 81 then return c end
  -- solution 值域
  for i = 1, 81 do
    local v = so[i]
    if type(v) ~= 'number' or v < 1 or v > 9 then return c end
  end
  -- puzzle 与 solution 兼容
  for i = 1, 81 do
    if pz[i] ~= 0 and pz[i] ~= so[i] then return c end
  end
  c.puzzle = pz
  c.solution = so
  c.seed = p.seed or 0
  c.difficulty = p.difficulty or 'medium'
  -- 题目变化 = 规则变化（对齐 chess SET_RULES）：清 ready 回 lobby，双方重新 ACK
  c.ready = {}
  state = "lobby"
  return c
end

-- ACK 准备门（对齐 chess）：双方都 ACK 后 state → ready，host 才可 START。
on_action_ACK = function(c, p)
  if state ~= "lobby" and state ~= "ready" then return c end
  if c.players[p.device_id] == nil then return c end
  c.ready[p.device_id] = true
  if c.host_id ~= nil and c.guest_id ~= nil
     and c.ready[c.host_id] == true and c.ready[c.guest_id] == true then
    state = "ready"
  end
  return c
end

on_action_START = function(c, p)
  if p.device_id ~= c.host_id then return c end
  -- 必须双方 ACK 就绪（state == 'ready'）且题目已生成
  if state ~= "ready" then return c end
  if c.puzzle == nil then return c end
  state = "playing"
  c.started_at_ms = now_ms()
  return c
end

-- 实时进度上报（填数/擦除后客户端 fire-and-forget）：
-- 写 c.progress[device_id] = {filled=..., errors=...}，对手进度条据此渲染。
on_action_PROGRESS = function(c, p)
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  local f = tonumber(p.filled) or 0
  local e = tonumber(p.errors) or 0
  c.progress[p.device_id] = { filled = f, errors = e }
  return c
end

on_action_SUBMIT = function(c, p)
  if state ~= "playing" then return c end
  if c.players[p.device_id] == nil then return c end
  if c.solution == nil then return c end
  local values = p.values
  if type(values) ~= 'table' or #values ~= 81 then return c end
  -- 对照 solution 全 81 格校验；错 → 原样返回（无副作用）
  for i = 1, 81 do
    if values[i] ~= c.solution[i] then return c end
  end
  -- 同一玩家重复提交不重复记录
  if c.finished_at_ms[p.device_id] == nil then
    c.finished_at_ms[p.device_id] = p.elapsed_ms or 0
    c.error_count[p.device_id] = p.errors or 0
    if c.winner_id == nil then
      c.winner_id = p.device_id
      state = "ended"
    end
  end
  return c
end

function now_ms()
  return math.floor(os.time() * 1000)
end
''';
