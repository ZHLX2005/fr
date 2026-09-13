// lib/core/sudoku/p2p/script/sudoku_script_lifecycle.dart
//
// kSudokuScript 的 lifecycle 段：on_init / on_join / on_leave。
//
// 与 chess 一致的纯字符串段；末尾必以 \n 结尾（assembler regex 边界）。
//
// 命名约定：`on_init = function(...)`（顶层全局赋值，assembler
// `_collectActionNames` 仅识别 `on_(?:action|init|join|leave)_\w+ = function`
// 模式；用 `function name(...)` 语法定义的全局不会被 assembler 检测到，
// 导出表的 `on_init = on_init` 会指向 nil）。

const String kSudokuScriptLifecycle = r'''
on_init = function(ctx, p)
  ctx.state = 'lobby'
  ctx.players = {}
  ctx.puzzle = nil
  ctx.solution = nil
  ctx.seed = 0
  ctx.difficulty = nil
  ctx.host_id = nil
  ctx.guest_id = nil
  ctx.started_at_ms = 0
  ctx.finished_at_ms = {}
  ctx.error_count = {}
  ctx.winner_id = nil
  return ctx
end

on_join = function(ctx, payload)
  local uid = payload.uid
  if ctx.state == 'lobby' and ctx.host_id == nil then
    ctx.host_id = uid
    ctx.players[uid] = true
    return {ok=true, role='host'}
  elseif ctx.state == 'lobby' and ctx.guest_id == nil and uid ~= ctx.host_id then
    ctx.guest_id = uid
    ctx.players[uid] = true
    return {ok=true, role='guest'}
  else
    return {ok=false, error='room_full'}
  end
end

on_leave = function(ctx, payload)
  local uid = payload.uid
  ctx.players[uid] = nil
  if uid == ctx.host_id then ctx.host_id = nil end
  if uid == ctx.guest_id then ctx.guest_id = nil end
  return {ok=true}
end
''';
