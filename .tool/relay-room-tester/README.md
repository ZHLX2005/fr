# relay-room-tester

Minimal e2e harness for relay rooms. Reuses the existing `RelayV3Transport` infra
(see `test/core/net_engine/relay_v3_transport_test.dart` and `relay_v3_integration_test.dart`).

## Files

- `emoji_e2e.dart` — emoji e2e harness (mock + live). Keep minimal; runnable with existing relay test infra.

## Emoji — what it verifies

| Check | Spec | How |
|-------|------|-----|
| **Cross-client visibility** | A sends `EMOJI`, B's `fetchSnapshot()` contains the event | Two `RelayV3Transport` on same `MockClient` (shared `rooms` map) |
| **seq dedup** | Same `device_id` + same `seq` → dropped, no version bump | Send `seq: 42` twice, assert version unchanged, length stays 1 |
| **Ring buffer cap 16** | Server ring keeps last 16, evicts oldest | Send 20 distinct EMOJI (2000 ms spaced to clear 1.5 s throttle), assert `length == 16` and retained `seq` are `5..20` |
| **Throttle 1.5 s** | Second send within 1500 ms dropped | `ts: 10000` then `ts: 10500` → dropped; `ts: 12000` → accepted |

Prod contract (key names): `c.emojiRing` / `c.emojis` / `c.emoji_events` are interchangeable —
overlay accepts all three (`emojisFromSnapshot` tries `emojis`, `emoji_events`, `recent_emojis` in order),
mock keeps all three aliases in sync, Lua (`lib/core/game_kit/emoji/emoji_script.dart`) writes all three.

## How to run

### Mock (CI-safe, no server required)

```bash
# from repo root
flutter test .tool/relay-room-tester/emoji_e2e.dart
# verbose
flutter test .tool/relay-room-tester/emoji_e2e.dart --reporter expanded
```

Mock tests are HTTP-only (via `RelayV3Transport.testApplyAction` / `testJoin` / `fetchSnapshot`
backed by `MockClient`), so no real `WebSocket` is opened — avoids the 30 s Timer hang that
`createRoom`/`joinRoom` would cause. All 4 mock tests pass offline (3 s total).

### Live relay (opt-in, hits real Go relay + real Lua VM)

Requires a running relay (default `http://127.0.0.1:8000`). The live group is **skipped** unless `LIVE=true`.

```bash
# dart-define form (preferred — works in flutter_test)
flutter test .tool/relay-room-tester/emoji_e2e.dart \
  --dart-define=RELAY_URL=http://127.0.0.1:8000 \
  --dart-define=LIVE=true

# env form (also accepted via Platform.environment fallback)
RELAY_URL=http://127.0.0.1:8000 flutter test .tool/relay-room-tester/emoji_e2e.dart --dart-define=LIVE=true

# verbose
flutter test .tool/relay-room-tester/emoji_e2e.dart --dart-define=LIVE=true --reporter=expanded
```

If `createRoom` fails (relay not reachable or Lua `definition` rejected), the live test **skips** rather than failing — it prints `[live] createRoom failed (...) skipping.` so local runs without a relay stay green.

## Manual verify steps (with two real devices / emulators)

1. Start relay: `go run ./cmd/relay` or `docker compose up relay` (see repo `doc/api/`).
2. On device A and device B, open chess (or any game that has mounted the emoji segment via `assembleLuaScript`).
3. Once inside a room (A creates, B joins with same 6-digit code):
   1. A taps an emoji (e.g. fire) → **B sees the floating animation within ~200 ms** (WS `snapshot` push; `EmojiOverlay` seq dedup).
   2. A double-taps the same emoji quickly → B sees it **once** (client seq dedup).
   3. A spams 3 emojis within 1 s → only the first is accepted (server 1.5 s `lastEmojiAt` gate).
   4. A sends 20 emojis slowly (>1.5 s apart) → inspect `snapshot.context['emojis']` / `emoji_events` → **exactly 16 entries, oldest 4 evicted** (`#emojiRing > 16` FIFO).
   5. Kill A's WS (airplane mode 5 s, then re-enable + `handle.rejoin()` path) → re-send emoji → B still receives (rejoin+sync guard, see `relay_v3_transport.dart: rejoin()`).
4. Without UI: add a temporary `handle.snapshots.listen((s) => debugPrint(jsonEncode(s.context['emojis'])))` in the room page, or `await handle.fetchSnapshot()` in a debugger.

## Lua contract (Phase 3 source of truth)

Prod segment: `lib/core/game_kit/emoji/emoji_script.dart` (`kEmojiScriptSegment`), spliced via
`lib/core/game_kit/emoji/lua_script_assembler.dart: assembleLuaScript(..., extraSegments: [kEmojiScriptSegment])`.
Until the game wiring is complete, `emoji_e2e.dart: kEmojiTestScript` embeds the same semantics
(ring 16 + coalesce same from+id + rate 1.5 s + legacy seq dedup) so the harness stays standalone.
When the prod segment is the canonical source, point the harness at it (replace `kEmojiTestScript`'s
value with `kEmojiScriptSegment` — tests must stay green).

## Troubleshooting

- `flutter test .tool/...` complains "Test file not found" → run from repo root, not from `.tool/`.
- Live test always skips → confirm `LIVE=true` was passed as `--dart-define`, not just env (env alone is best-effort fallback).
- `MockClient` path 404 → the mock only handles `/api/v3/relay/rooms*` (create/join/actions/snapshot/leave); other paths intentionally 404.
- `dart analyze .tool/...` warns `invalid_use_of_visible_for_testing_member` on `testApplyAction`/`testJoin` — expected; the file is a test harness (`.tool/` is not shipped). Warnings are non-blocking (`dart analyze` has 0 errors, `flutter test` passes).
