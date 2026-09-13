// lib/core/sudoku/p2p/script/sudoku_script_actions.dart
//
// kSudokuScript 的 actions 段：SET_PUZZLE / START / SUBMIT。
//
// 所有 handler 写在导出表（由 assembler 末尾生成）。
//
// 命名约定：`on_action_SET_PUZZLE = function(...)`（assembler 仅识别
// `on_action_X = function(...)` 模式 —— 见 lua_script_assembler.dart
// `_collectActionNames` 正则）。

const String kSudokuScriptActions = r'''
on_action_SET_PUZZLE = function(ctx, payload)
  -- 仅 host 可调
  if payload.uid ~= ctx.host_id then return {ok=false, error='not_host'} end
  local p = payload.puzzle
  local s = payload.solution
  if type(p) ~= 'table' or #p ~= 81 then return {ok=false, error='bad_puzzle_len'} end
  if type(s) ~= 'table' or #s ~= 81 then return {ok=false, error='bad_solution_len'} end
  -- solution 值域
  for i = 1, 81 do
    local v = s[i]
    if type(v) ~= 'number' or v < 1 or v > 9 then
      return {ok=false, error='bad_solution_value'}
    end
  end
  -- puzzle 与 solution 兼容
  for i = 1, 81 do
    if p[i] ~= 0 and p[i] ~= s[i] then
      return {ok=false, error='puzzle_solution_mismatch'}
    end
  end
  ctx.puzzle = p
  ctx.solution = s
  ctx.seed = payload.seed or 0
  ctx.difficulty = payload.difficulty or 'medium'
  return {ok=true}
end

on_action_START = function(ctx, payload)
  if payload.uid ~= ctx.host_id then return {ok=false, error='not_host'} end
  if ctx.guest_id == nil then return {ok=false, error='no_guest'} end
  if ctx.puzzle == nil then return {ok=false, error='no_puzzle'} end
  ctx.state = 'playing'
  ctx.started_at_ms = now_ms()
  return {ok=true, broadcast_puzzle=ctx.puzzle}
end

on_action_SUBMIT = function(ctx, payload)
  if ctx.state ~= 'playing' then return {ok=false, error='not_playing'} end
  if not ctx.players[payload.uid] then return {ok=false, error='not_in_room'} end
  local values = payload.values
  if type(values) ~= 'table' or #values ~= 81 then return {ok=false, error='bad_values_len'} end
  -- 校验答案
  for i = 1, 81 do
    if values[i] ~= ctx.solution[i] then return {ok=false, error='wrong_answer'} end
  end
  ctx.finished_at_ms[payload.uid] = payload.elapsed_ms or 0
  ctx.error_count[payload.uid] = payload.errors or 0
  if ctx.winner_id == nil then
    ctx.winner_id = payload.uid
    ctx.state = 'ended'
  end
  return {ok=true, winner=ctx.winner_id}
end

function now_ms()
  return math.floor(os.time() * 1000)
end
''';
