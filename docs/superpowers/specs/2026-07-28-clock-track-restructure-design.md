# Clock + Beat + Track — Design Spec

**Date**: 2026-07-28
**Status**: Approved (pending written review)
**Path**: `D:/a_other/dart/prj/demo1/flutter_application_1/docs/superpowers/specs/2026-07-28-clock-track-restructure-design.md`

## Context

The current Clock demo (`lib/lab/demos/clock_demo.dart`, 1756 lines) uses a hand-drawn wave divider to split the screen between a clock grid (top) and a record list (bottom). It does not integrate with the existing Oboe-based metronome (`lib/lab/demos/metronome/`), and it has no concept of a "track" — a multi-segment training plan built from existing clocks.

The user wants to:

1. **Restructure the clock UI in Zen Journal style** (warm paper palette, no special fonts, real buttons ≥44px, bottom Tab Bar).
2. **Add a beat option to each clock** (custom time signature, slow BPM for workout pace) that wires into the existing `MetronomeFFI`.
3. **Add a Track feature** — an arranger that copies clock metadata into segments, plus a runner page, records, and a dashboard.
4. **Preserve core clock features**: negative/overflow timing, "create clock from record", shake-to-start, home screen widget sync, and all existing dialogs/pickers.
5. **Save the current feature inventory as a doc** so future work doesn't regress.

The user explicitly opted for **Path B (one-shot refactor)** and **no migration** (old clock data is dropped). The user also dropped vibration feedback in favor of pure metronome ticks.

The style is **Zen Journal** (warm paper) with **no special fonts**.

## Goals

- A user can open the Clock demo, see 3 tabs (Clocks / Tracks / Dashboard), and switch between them with a real bottom Tab Bar (no wave divider).
- A user can edit a clock and toggle a beat (BPM + pattern); once the clock is running, the metronome ticks at that BPM.
- A user can create a Track by selecting clocks from a palette; the track's segments snapshot the clock's `durationSeconds`, `bpm`, and `beatPattern` so the original clock can be edited later without affecting the running track.
- A user can ▶ Run a Track, watch it auto-advance through segments, hear the beat (if any) and short tick at segment transitions, and a longer tick at the end.
- A user can see today's totals and recent records on a Dashboard tab.
- The existing Clock's overflow timing, swipe-record actions, shake-to-start, and home widget all keep working.

## Non-Goals

- Drag-and-drop reordering of track segments. v1 uses up/down arrow buttons per segment.
- Multiple beats playing simultaneously. The Oboe stream is a singleton.
- Migrating old `lab_clocks` JSON. v2 keys are independent; the old data is left in SharedPreferences but not loaded.
- Vibration on countdown end. Replaced with metronome ticks.
- iOS / desktop / web audio. Oboe is Android-only; on other platforms, beat is silent but the UI still works.
- Cross-track beat (multiple segments beating at different tempos concurrently). The current segment's tempo wins; previous segment stops on transition.

## Architecture

```
                  ┌─────────────────────────────────────┐
                  │           BeatCoordinator            │
                  │  (singleton owner of MetronomeFFI)   │
                  └────────────────┬────────────────────┘
                                   │ setBpm / play / pause
                                   ▼
                            MetronomeFFI  ────► libmetronome.so (Oboe)
                                   ▲
                                   │
              ┌────────────────────┴────────────────────┐
              │                                         │
   LabClockProvider  ◄─────tick ownership────►  LabTrackProvider
   (clock running)        (only one)            (track running)
        │                                           │
        ├─ _syncToWidget                            ├─ _syncToWidget
        ▼                                           ▼
   ClockWidgetService                        ClockWidgetService
        │                                           │
        └──────────► SharedPreferences ◄─────────────┘
                  'lab_clocks_v2'
                  'lab_clock_records_v2'
                  'lab_tracks'
                  'lab_track_records'
                  'shake_to_start_enabled'
```

### Data layer

#### `LabClock` (model — modify)

Add two nullable fields:

| Field          | Type      | Default | Notes                                       |
| -------------- | --------- | ------- | ------------------------------------------- |
| `bpm`          | `int?`    | `null`  | 20..300, null means no beat                 |
| `beatPattern`  | `String?` | `null`  | key into `MetronomePresets.patterns` map    |

These fields are added to `copyWith` and to the JSON-serializable codegen (`lab_clock.g.dart` regenerated). Old JSON without these keys loads with `null`.

The `LabClock.copyWith` quirk (every non-null field passed) is preserved — the editor sheet always passes all current values, never relying on `??`.

#### `LabTrack` (model — new file `lib/lab/demos/clock/models/lab_track.dart`)

```dart
@JsonSerializable()
class LabTrack {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final List<LabTrackSegment> segments;
  // isRunning / remainingSeconds are runtime state, not persisted
  // when running, copy segments into a runtime list in LabTrackProvider
}

@JsonSerializable()
class LabTrackSegment {
  final String clockId;                   // reference; may point to deleted clock
  final String snapshotTitle;             // copied at add-time
  final String? snapshotColor;
  final int snapshotDurationSeconds;      // copied at add-time
  final int? snapshotBpm;                 // copied at add-time
  final String? snapshotBeatPattern;      // copied at add-time
}
```

#### `LabTrackRecord` (model — new file)

```dart
@JsonSerializable()
class LabTrackRecord {
  final String id;
  final String trackId;
  final String trackTitle;
  final String? customTitle;
  final DateTime startTime;
  final DateTime? endTime;
  final int totalDurationSeconds;
  final bool completed;
  final int? accumulatedSeconds;
  final int segmentIndex;                 // last completed segment index
  final List<int> perSegmentSeconds;      // actual elapsed per segment
}
```

#### Storage keys

- `'lab_clocks_v2'` — `json.encode(List<LabClock>)`. Replaces `'lab_clocks'`.
- `'lab_clock_records_v2'` — replaces `'lab_clock_records'`.
- `'lab_tracks'` — `json.encode(List<LabTrack>)`.
- `'lab_track_records'` — `json.encode(List<LabTrackRecord>)`.
- `'shake_to_start_enabled'` — unchanged.

`LabClockProvider` constructor no longer auto-loads; instead the demo page's `initState` calls `loadClocks()` (existing pattern).

### Provider layer

#### `LabClockProvider` (modify, preserve API)

Add to existing class:

- `String? _activeBeatClockId` — tracks which clock currently owns the metronome.
- `String? get activeBeatClockId` (read-only).
- `void setBeat(String clockId, {int? bpm, String? beatPattern})` — overwrites clock's beat fields; calls `_saveClocks()`.
- `void clearBeat(String clockId)` — sets `bpm = null`; calls `_saveClocks()`.
- In `_startTimer`'s per-second loop, when a clock's `isRunning` flips true and `bpm != null`, request beat ownership from `BeatCoordinator`. When `isRunning` flips false, release.
- The existing `startCountdown` / `pauseCountdown` / `resetCountdown` methods are preserved. They call into a new private helper `_syncBeatForClock(clockId)` to take/release beat ownership.
- **Drop `_vibrate3Seconds`, `_playNotificationSound`, `_vibrate`** — no more `HapticFeedback` / `audioplayers` (per user request, all vibration removed; audio cue is the metronome tick). The `AudioPlayer` field and its `dispose` are also removed. The `MethodChannel('io.github.xiaodouzi.fr/clock')` is dropped. (Native side stays — other code may use it.)
- Drop `import 'package:audioplayers/audioplayers.dart';` and `import 'package:flutter/services.dart';` if HapticFeedback was the only use.
- Keep the home screen widget sync (`_syncToWidget`), but it now syncs the first clock OR the first track (whichever exists).

#### `LabTrackProvider` (new file `lib/lab/demos/clock/providers/lab_track_provider.dart`)

`ChangeNotifier` with:

- `List<LabTrack> _tracks`
- `List<LabTrackRecord> _records`
- `LabTrack? _activeTrack` — runtime state
- `int _currentSegmentIndex`
- `DateTime? _segmentStartTime`
- `int _segmentStartRemaining`
- `Timer? _timer`
- Methods: `loadTracks()`, `createTrack`, `updateTrack`, `deleteTrack`, `startTrack(trackId)`, `pauseTrack()`, `skipSegment()`, `stopTrack()`, `getRecordLiveDuration(record)`.
- Same startTime-relative math as `LabClockProvider` for app-resume correctness.
- On segment boundary: `BeatCoordinator.requestOwnership(providerId: 'track', bpm, beatPattern)`, short tick.
- On track end: release ownership, longer tick.

#### `BeatCoordinator` (new file `lib/lab/demos/clock/providers/beat_coordinator.dart`)

Static singleton class that owns `MetronomeFFI` exclusively.

```dart
class BeatCoordinator {
  static String? _ownerId;
  static int? _lastBpm;
  static String? _lastPattern;

  static String? get ownerId => _ownerId;

  /// Returns true if ownership was taken (or already owned by caller).
  /// If another owner, that owner is notified to mark itself as "beat silent".
  static bool requestOwnership({
    required String providerId,
    int? bpm,
    String? beatPattern,
  }) {
    if (_ownerId != null && _ownerId != providerId) {
      // previous owner is told via static callback
      _onBeatenOut?.call(_ownerId!);
    }
    _ownerId = providerId;
    if (bpm != null) MetronomeFFI.setBpm(bpm.toDouble());
    if (beatPattern != null) {
      final pattern = MetronomePresets.patterns[beatPattern];
      if (pattern != null) {
        MetronomeFFI.setBeatsPerBar(pattern.beatsPerMeasure);
        for (var i = 0; i < pattern.beatsPerMeasure; i++) {
          final isAccent = pattern.accentIndices.contains(i);
          MetronomeFFI.setBeatAccentLevel(i, isAccent ? 2 : 0);
        }
      }
    }
    MetronomeFFI.play();
    return true;
  }

  static void releaseOwnership(String providerId) {
    if (_ownerId != providerId) return;
    _ownerId = null;
    MetronomeFFI.pause();
  }

  static ValueChanged<String>? _onBeatenOut;
  static void registerBeatenOutCallback(ValueChanged<String> cb) => _onBeatenOut = cb;
}
```

Both providers call `BeatCoordinator.registerBeatenOutCallback` in their constructors. When their `providerId` is in the callback arg, they mark their internal state as `beatSilent: true` so the UI can grey out the beat indicator (but the clock/track still ticks; only audio stops).

### UI layer

#### `clock_demo.dart` restructure

The current `ClockDemo extends DemoPage` is replaced with a smaller shell:

```dart
class ClockDemo extends DemoPage {
  @override String get title => 'Clock';
  @override String get slug => 'clock';
  @override String get description => '时钟 · 编排 · 节拍';
  @override bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LabClockProvider()..loadClocks()),
        ChangeNotifierProvider(create: (_) => LabTrackProvider()..loadTracks()),
      ],
      child: const _ClockShell(),
    );
  }
}

class _ClockShell extends StatefulWidget { ... }

class _ClockShellState extends State<_ClockShell> {
  int _tabIndex = 0;

  Widget _buildTab(int index) {
    switch (index) {
      case 0: return const ClocksTab();
      case 1: return const TracksTab();
      case 2: return const DashboardTab();
    }
    ...
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tabIndex, children: [...]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.access_time), label: 'Clocks'),
          NavigationDestination(icon: Icon(Icons.queue_music), label: 'Tracks'),
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
        ],
      ),
    );
  }
}
```

The shake-to-start toggle moves into a drawer (or a small button in the app bar of `ClocksTab`).

#### `ClocksTab` (new widget in `clock_demo.dart` or a new file)

- App bar with title "Clocks", trailing drawer button.
- GridView of `LabClockCard` (rebuilt from the existing `_ClockCard` widget, with the addition of a small beat dot + bpm text when `clock.bpm != null`).
- The wave divider is removed.
- The existing `_buildModernRecordItem` is moved to a separate `RecordListSection` widget that appears below the grid as a scrollable list.
- Long-press a record → rename dialog. Swipe left → Create / Delete. **Keep the existing `LabClockRecord` swipe action UX exactly as-is.**
- "+" FAB in the bottom-right opens the `ClockEditorSheet`.

#### `TracksTab` (new widget)

- App bar with title "Tracks".
- ListView of `LabTrackCard`: title, segment count, total duration, "▶ Run" button (disabled if any clock is currently running).
- "Run" opens `TrackRunnerPage` via `Navigator.push`.
- "Edit" / "+" FAB → `TrackEditorPage`.

#### `DashboardTab` (new widget)

- App bar with title "Dashboard".
- Three stat tiles: "Today: Xm Ys", "Clocks completed: N", "Tracks completed: M".
- A "Recent" section listing the latest 5 records (merged `LabClockRecord` + `LabTrackRecord`, sorted by start time desc, each row tappable to its detail).

#### `ClockEditorSheet` (rebuilt, kept functionality)

The current `_showClockEditor` is replaced with a clean version. New fields:

- "Beat" toggle (off by default).
- If on: BPM stepper (default 60, range 20..300) and a chip row of patterns from `MetronomePresets.patterns`.
- A small live `BeatIndicator` below the chip row previews the beat visually (using `MetronomeController` for preview only, or a stateless CSS-like keyframe if FFI is too heavy here — implementer's call).

The 8-color picker, h-m-s wheel pickers, title/description inputs all preserved.

#### `TrackEditorPage` (new file `lib/lab/demos/clock/track_editor_page.dart`)

- App bar: "Edit Track" or "New Track".
- Title input + description input.
- "Source" section: horizontal scroll row of `LabClock` chips (palette). Each shows title + duration + color dot. Tap to append to track.
- "Sequence" section: list of placed segments as rows with up/down/× buttons. Total duration at the bottom.
- Save / Cancel buttons in footer.

#### `TrackRunnerPage` (new file `lib/lab/demos/clock/track_runner_page.dart`)

- Full-screen, prefer-full-screen.
- Top: track title (small).
- Big: current segment name + remaining time (mono font).
- Mid: progress bar (segment-local + track-global stacked).
- Beat indicator (sage dot row) below the time, visible only when current segment has bpm.
- Bottom: Pause/Resume · Skip Segment · Stop buttons.
- At segment end: short metronome accent on the new downbeat; auto-advance to next segment.
- At track end: release beat, longer metronome pattern (2 strong + 1 weak as a "done" cue), then return to `TracksTab`.

#### `TrackRecordsPage` (new file)

Same UX as the existing record list, but bound to `LabTrackRecord` and the `LabTrackProvider.records`. Accessible from a small "history" icon in the `TracksTab` app bar.

### Zen styling rules

- Palette: bg `#F4F1EA`, text `#2C2C2C`, hairline `#D9D5C8`, sage accent `#7A9A7E`, muted red `#A0594A`.
- Font: `font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;`. Mono for digits: `SF Mono, Menlo, Consolas, monospace`.
- Border-radius: 4px on chips, 6px on cards, 0 on track runner (matches the printed-trainer feel).
- Dotted borders (`border-style: dotted`) for placeholder zones (e.g. empty track sequence "drag a clock here").
- All buttons ≥ 44x44px. No underline text-links for actions. Color is encoded by `BeatIndicator` dot state, not by text color.
- No shadows, no gradients.

## Phases (single-shot refactor per user choice)

The user chose Path B (one-shot refactor) but I will still sequence work into committable phases for review checkpoints:

### Phase 1 — Spec + feature inventory doc

- Create this spec.
- Create `.tool/clock-redesign-lottery/feature-inventory.md` documenting every existing feature with file paths/line numbers (so reviewers can verify nothing is missed).

### Phase 2 — Data layer

- Add `bpm` / `beatPattern` to `LabClock` + regenerate `lab_clock.g.dart`.
- New file `lib/lab/demos/clock/models/lab_track.dart` (`LabTrack`, `LabTrackSegment`).
- New file `lib/lab/demos/clock/models/lab_track_record.dart` (`LabTrackRecord`).
- Generate `.g.dart` files via `dart run build_runner build`.
- Switch `LabClockProvider` storage key to `lab_clocks_v2` / `lab_clock_records_v2`.
- `flutter analyze` must pass.

### Phase 3 — Providers

- New file `lib/lab/demos/clock/providers/beat_coordinator.dart`.
- New file `lib/lab/demos/clock/providers/lab_track_provider.dart`.
- Modify `LabClockProvider`: add `setBeat` / `clearBeat`, hook beat into `startCountdown` / `pauseCountdown` / `resetCountdown`, drop vibration code.
- `flutter analyze` must pass.

### Phase 4 — UI restructure

- Replace `clock_demo.dart` body with `MultiProvider` + tab shell.
- New file `lib/lab/demos/clock/clocks_tab.dart` (or inline if short).
- New file `lib/lab/demos/clock/tracks_tab.dart`.
- New file `lib/lab/demos/clock/dashboard_tab.dart`.
- New file `lib/lab/demos/clock/track_editor_page.dart`.
- New file `lib/lab/demos/clock/track_runner_page.dart`.
- New file `lib/lab/demos/clock/track_records_page.dart`.
- Modify `ClockEditorSheet` to add Beat section.

### Phase 5 — CI verification

- `flutter analyze lib/` — 0 errors.
- `flutter build apk --debug` — must succeed (validates CMake / Oboe link).
- Manual smoke test plan:
  1. Open Clock demo → see 3 tabs, Zen style, no wave divider.
  2. Add a clock 5:00 with beat 60bpm 4/4. Verify the card shows a beat dot + "60bpm".
  3. Tap ▶ on the clock → metronome starts; verify in another Oboe app that the audio thread is alive.
  4. Wait past 5:00 → overflow counter visible (negative time). Beat continues.
  5. Reset clock → record appears in records. Swipe left → "Create" → new clock created.
  6. Switch to Tracks tab → tap + → drag 2 clocks into the sequence → save.
  7. Tap ▶ Run on track → runner page opens → first segment counts down → segment end → second segment starts → track end.
  8. Switch to Dashboard → see "Today: 5m 0s" and 1 record.
  9. Open app drawer (or settings) → toggle shake-to-start → shake device → first stopped clock starts.
  10. Kill app and reopen mid-run → countdown re-syncs from startTime.

## Risks

| Risk                                                                      | Mitigation                                                                                 |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `MetronomeFFI.setBpm` may drift after rapid changes                      | Mirror `MetronomeController.setBpm` pattern: clamp bpm to 20..300 before passing to FFI.   |
| Two providers both request beat in the same frame                        | `BeatCoordinator.requestOwnership` is synchronous and re-entrant — last writer wins.       |
| Oboe stream can't resume after `pause` + `play` cycles                   | `MetronomeFFI.pause()` only stops the audio callback; the stream stays open. (Verified by reading `metronome.cpp`.) |
| `LabClock.copyWith` quirky null-fallback behavior                         | Editor sheet always passes the full set of fields; tests assert the round-trip JSON.        |
| Beat preview in the editor sheet accidentally drives the FFI             | Editor preview uses an isolated `AnimationController` on a synthetic beat stream, no FFI.   |
| Drag-and-drop in track editor (skipped in v1)                            | Use up/down/× buttons; document the gap.                                                    |
| `flutter build apk` finds CMake/oboe errors analyze can't see            | Run `flutter build apk --debug` in Phase 5 (analyze + CI are not enough).                   |
| Home widget only syncs one entity                                        | `_syncToWidget` writes the first clock if any exist, else the first track.                 |
| Losing beat on app background                                            | On `AppLifecycleState.resumed`, both providers re-request beat ownership if their entity is still running. |
| The "create clock from record" UX is implemented in the existing provider; the new `LabClockProvider` may inadvertently drop it | Keep the `onCreate` callback in `_RecordSwipeAction`; do not refactor that widget.          |

## Verification

1. `flutter analyze lib/` reports 0 errors.
2. `flutter build apk --debug` succeeds (validates native Oboe link).
3. Manual smoke test (10 steps above) all pass on a real Android device.
4. Visual: Zen palette confirmed (warm paper, sage accent, dotted borders on placeholders).
5. Visual: all buttons ≥ 44x44px (spot-check with a ruler overlay).
6. Visual: no serif, no italic, no `Georgia` / `Playfair` in source (grep).
7. The `.tool/clock-redesign-lottery/feature-inventory.md` doc lists every preserved feature; the user can read it and check off.
8. Old `lab_clocks` JSON is ignored (not deleted from SharedPreferences) but not loaded.

## Files to create / modify

**Create**:
- `lib/lab/demos/clock/models/lab_track.dart`
- `lib/lab/demos/clock/models/lab_track.g.dart`
- `lib/lab/demos/clock/models/lab_track_record.dart`
- `lib/lab/demos/clock/models/lab_track_record.g.dart`
- `lib/lab/demos/clock/providers/beat_coordinator.dart`
- `lib/lab/demos/clock/providers/lab_track_provider.dart`
- `lib/lab/demos/clock/clocks_tab.dart`
- `lib/lab/demos/clock/tracks_tab.dart`
- `lib/lab/demos/clock/dashboard_tab.dart`
- `lib/lab/demos/clock/track_editor_page.dart`
- `lib/lab/demos/clock/track_runner_page.dart`
- `lib/lab/demos/clock/track_records_page.dart`
- `lib/lab/demos/clock/clock_editor_sheet.dart`
- `.tool/clock-redesign-lottery/feature-inventory.md`
- `docs/superpowers/specs/2026-07-28-clock-track-restructure-design.md` (this file)

**Modify**:
- `lib/lab/demos/clock/models/lab_clock.dart` (add `bpm` / `beatPattern`)
- `lib/lab/demos/clock/models/lab_clock.g.dart` (regenerated)
- `lib/lab/demos/clock/providers/lab_clock_provider.dart` (add beat, drop vibration, switch storage key)
- `lib/lab/demos/clock_demo.dart` (replace body with tab shell)

**Reuse** (no change):
- `lib/lab/demos/metronome/ffi_bindings.dart` — `MetronomeFFI` is reused as-is.
- `lib/lab/demos/metronome/const_metronome.dart` — `MetronomePresets.patterns` is the source of beat patterns.
- `lib/lab/demos/clock/utils/clock_color_util.dart` — color overtime calculations apply unchanged.
- The home widget service at `lib/native/home_widget/clock_widget_service.dart` — receives the same data shape.
