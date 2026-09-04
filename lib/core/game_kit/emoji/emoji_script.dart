// lib/core/game_kit/emoji/emoji_script.dart
//
// Shared EMOJI Lua segment — game-agnostic, opt-in via LuaScriptAssembler.
//
// ## Contract
//
// - Handler: `on_action_EMOJI` (payload: { emojiId: string, ts?: number }).
// - Rate: 1.5 s per player via `c.lastEmojiAt[device_id]` (ms, `p.ts` or `os.time()*1000`).
// - Buffer: ring 16 (`c.emojiRing`, max 16 entries, FIFO eviction).
// - Coalesce: consecutive same `from + id` bumps `count` + refreshes `seq`/`ts`
//   instead of pushing a new entry (spam tap collapses to one row with counter).
// - Seq: monotonic `c.emojiSeq` (1-based) assigned to every accepted event;
//   coalesced bump also advances seq so clients can order by seq.
// - Auth: only `c.players[device_id]` may emit (spectators rejected).
//
// ## Placement
//
// This segment is NOT a standalone script — it is concatenated after the
// lifecycle + actions segments and BEFORE the generated `return { definition … }`
// export table. The assembler rebuilds that table to include `on_action_EMOJI`
// when this segment is present (so callers never hand-edit returns).
//
// Splicing order (via assembleLuaScript):
//   lifecycle → actions → extraSegments (this segment) → generated return
//
// Keep trailing `\n` in the raw string so `_functionBlock` regex boundaries
// (`\non_(?:action|join|leave|init)_\w+ = function`) remain stable.

const String kEmojiScriptSegment = r'''
-- ════════════════════════════════════════════════════════════════
-- Shared EMOJI segment (game_kit/emoji)
-- Rate 1.5s via c.lastEmojiAt, ring 16 (c.emojiRing), coalesce same id
-- ════════════════════════════════════════════════════════════════

function _emojiRateLimited(c, p, now)
  c.lastEmojiAt = c.lastEmojiAt or {}
  local last = c.lastEmojiAt[p.device_id] or 0
  if now - last < 1500 then return true end
  c.lastEmojiAt[p.device_id] = now
  return false
end

on_action_EMOJI = function(c, p)
  if c.players == nil or c.players[p.device_id] == nil then return c end
  local id = p.emoji_id or p.emojiId or p.emoji
  if type(id) ~= "string" or id == "" then return c end
  if #id > 32 then return c end
  local now = p.ts or (os.time() * 1000)
  if _emojiRateLimited(c, p, now) then return c end
  c.emojiRing = c.emojiRing or {}
  c.emojiSeq = (c.emojiSeq or 0) + 1
  local last = c.emojiRing[#c.emojiRing]
  if last ~= nil and last.from == p.device_id and last.id == id then
    last.count = (last.count or 1) + 1
    last.seq = c.emojiSeq
    last.ts = now
    return c
  end
  table.insert(c.emojiRing, {
    id = id,
    emoji_id = id,
    from = p.device_id,
    ts = now,
    seq = c.emojiSeq,
    count = 1,
  })
  if #c.emojiRing > 16 then
    table.remove(c.emojiRing, 1)
  end
  return c
end
''';
