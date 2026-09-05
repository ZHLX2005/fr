// lib/core/game_kit/chat/chat_script.dart
//
// Shared CHAT Lua segment — game-agnostic, opt-in via LuaScriptAssembler.
//
// ## Contract
//
// - Handler: `on_action_CHAT` (payload: { text: string, alias?: string, ts?: number }).
// - Rate: 1.5 s per player via `c.lastChatAt[device_id]`.
// - Buffer: ring 16 (`c.chatRing`, FIFO eviction).
// - Seq: monotonic `c.chatSeq` (1-based).
// - Auth: only `c.players[device_id]` may emit (spectators rejected).
// - Text: non-empty string, trimmed server-side by length check only (≤ 80).
//
// Keep trailing `\n` so assembler `_functionBlock` regex boundaries stay stable.

const String kChatScriptSegment = r'''
-- ════════════════════════════════════════════════════════════════
-- Shared CHAT segment (game_kit/chat)
-- Rate 1.5s via c.lastChatAt, ring 16 (c.chatRing), text ≤ 80
-- ════════════════════════════════════════════════════════════════

function _chatRateLimited(c, p, now)
  c.lastChatAt = c.lastChatAt or {}
  local last = c.lastChatAt[p.device_id] or 0
  if now - last < 1500 then return true end
  c.lastChatAt[p.device_id] = now
  return false
end

on_action_CHAT = function(c, p)
  if c.players == nil or c.players[p.device_id] == nil then return c end
  local text = p.text or p.msg
  if type(text) ~= "string" then return c end
  -- strip leading/trailing spaces (simple)
  text = text:match("^%s*(.-)%s*$") or text
  if text == "" then return c end
  if #text > 80 then return c end
  local now = p.ts or (os.time() * 1000)
  if _chatRateLimited(c, p, now) then return c end
  c.chatRing = c.chatRing or {}
  c.chatSeq = (c.chatSeq or 0) + 1
  table.insert(c.chatRing, {
    kind = "text",
    text = text,
    from = p.device_id,
    alias = p.alias,
    ts = now,
    seq = c.chatSeq,
    id = "c" .. tostring(c.chatSeq),
  })
  if #c.chatRing > 16 then
    table.remove(c.chatRing, 1)
  end
  return c
end
''';
