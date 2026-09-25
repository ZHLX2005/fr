// lib/core/sudoku/p2p/script/sudoku_script_lifecycle.dart
//
// kSudokuScript 的 lifecycle 段：on_init / on_join / on_leave。
//
// 与 chess/go 完全一致的服务端契约（v2 修复）：
//   · handler 签名 `(c, p)`：c 是 context 表，p 是事件 payload；
//   · 身份字段：`p.device_id` / `p.alias`（relay join/init payload 的真实
//     字段名 —— v1 误用 `payload.uid`，该字段永远为 nil，导致
//     `players[nil]=true` 抛 "table index is nil"、host_id/guest_id 永远
//     为空、房间永远无法开始对局）；
//   · 状态变量：全局 `state`（snapshot 的 state 字段来自它，不是 c.state）；
//   · 返回约定：handler 原地改 c 并 `return c`；拒绝 = 原样返回 c，
//     不返回 `{ok=...}`（v1 的返回约定会让服务端把返回值当新 context）。
//
// 命名约定：`on_init = function(...)`（顶层全局赋值，assembler
// `_collectActionNames` 仅识别 `on_(?:action|init|join|leave)_\w+ = function`
// 模式；用 `function name(...)` 语法定义的全局不会被 assembler 检测到，
// 导出表的 `on_init = on_init` 会指向 nil）。
//
// 段末尾必须以 \n 结尾（拼接处保持换行，避免 `_functionBlock` regex 块边界漂移）。

const String kSudokuScriptLifecycle = r'''
on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.guest_id = nil
  c.ready = {}           -- {[device_id] = true}（ACK 准备门，对齐 chess）
  c.puzzle = nil
  c.solution = nil
  c.seed = 0
  c.difficulty = nil
  c.started_at_ms = 0
  c.finished_at_ms = {}
  c.error_count = {}
  c.progress = {}        -- {[device_id] = {filled=int, errors=int}}
  c.winner_id = nil
  c.disconnected = {}    -- {[device_id] = true}（瞬态断线标记）
  state = "lobby"
  return c
end

-- 同 device_id 重连识别（断线恢复）；guest 满员拒绝。
on_join = function(c, p)
  if c.players[p.device_id] ~= nil then
    c.disconnected[p.device_id] = nil
    return c
  end

  if c.guest_id ~= nil then
    return c
  end

  c.players[p.device_id] = p.alias
  c.guest_id = p.device_id
  return c
end

-- 掉线重连 / 玩家退出（对齐 chess v3 语义）：
--   · playing/ready 内离开 → 瞬态断线处理：只标 disconnected，保留玩家槽位，
--     同 device_id 重新 join 即可恢复（on_join 清标记）。
--   · lobby 内 guest 离开 → 清 guest 槽；host 离开 → 终局（host_left_lobby）。
--   · ended 内离开 → 保持 ended。
on_leave = function(c, p)
  if state == "playing" or state == "ready" then
    c.disconnected[p.device_id] = true
  elseif state == "lobby" then
    c.players[p.device_id] = nil
    c.ready[p.device_id] = nil
    c.disconnected[p.device_id] = nil
    if p.device_id == c.guest_id then
      c.guest_id = nil
    elseif p.device_id == c.host_id then
      state = "ended"
      c.end_reason = "host_left_lobby"
    end
  elseif state == "ended" then
    c.disconnected[p.device_id] = true
  end
  return c
end
''';
