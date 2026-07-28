# Clock + Beat + Track Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure the existing Clock demo into a Zen-Journal-styled 3-tab app (Clocks / Tracks / Dashboard), add per-clock BPM + beat pattern (custom time signature, wired to Oboe via `MetronomeFFI`), and add a Track feature that runs multiple clock-snapshotted segments in sequence. Drop all vibration. Drop the wave divider. Drop old `lab_clocks` data.

**Architecture:** A `BeatCoordinator` static singleton is the single owner of `MetronomeFFI`. `LabClockProvider` (modified) and `LabTrackProvider` (new) both talk to it via `requestOwnership(providerId, bpm, pattern)`. Tracks snapshot clock metadata at edit-time so editing a clock later doesn't break a running track. UI splits into 3 tabs with a real bottom `NavigationBar`; the existing wave divider is removed.

**Tech Stack:** Flutter `^3.11.1` (Dart SDK), `provider ^6.x`, `json_annotation + build_runner`, existing Oboe `libmetronome.so` + `MetronomeFFI`, `shared_preferences`, `audioplayers` (removed from clock code).

**Spec:** `docs/superpowers/specs/2026-07-28-clock-track-restructure-design.md`

---

## Global Constraints

- **Visual style:** Zen palette. Background `#F4F1EA`, text `#2C2C2C`, hairline `#D9D5C8`, sage accent `#7A9A7E`, muted red `#A0594A`. Border-radius: 4px chips, 6px cards.
- **Fonts:** `font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;`. Digits only: `SF Mono, Menlo, Consolas, monospace`. **NO** Georgia / Playfair / serif / italic.
- **Touch targets:** All interactive elements ≥ 44x44px.
- **Storage keys:** `'lab_clocks_v2'`, `'lab_clock_records_v2'`, `'lab_tracks'`, `'lab_track_records'`, `'shake_to_start_enabled'`. Old `'lab_clocks'` data is ignored, not deleted.
- **BPM range:** 20..300 (per spec; user prefers 30..60 in practice).
- **Pattern source:** keys must exist in `MetronomePresets.patterns` (`lib/lab/demos/metronome/const_metronome.dart`).
- **Vibration:** Drop all `HapticFeedback` / `_vibrate*` / `audioplayers` / `MethodChannel('io.github.xiaodouzi.fr/clock')` references in clock code. Replace end-of-countdown feedback with metronome tick.
- **Beat singleton:** Only one entity (clock OR track) can hold `MetronomeFFI` at a time. The new owner kicks the previous owner out via `BeatCoordinator`.
- **No migration:** Old `'lab_clocks'` JSON is not loaded. The new provider reads only `'lab_clocks_v2'`.
- **Test files stay local:** `test/lab/` is git-ignored per `.gitignore:73`. Test files are written, run locally, but NOT committed. Commit commands in each task below drop the test file path.
- **Verify with:** `flutter analyze lib/` (must pass after every task that touches Dart), and final `flutter build apk --debug` at the end.
- **Commit cadence:** Every task ends with a `git commit` of production code only.

---

## File Structure

**Create:**
- `lib/lab/demos/clock/models/lab_track.dart` — `LabTrack` + `LabTrackSegment` (JsonSerializable)
- `lib/lab/demos/clock/models/lab_track.g.dart` — generated
- `lib/lab/demos/clock/models/lab_track_record.dart` — `LabTrackRecord` (JsonSerializable)
- `lib/lab/demos/clock/models/lab_track_record.g.dart` — generated
- `lib/lab/demos/clock/providers/beat_coordinator.dart` — `BeatCoordinator` static singleton
- `lib/lab/demos/clock/providers/lab_track_provider.dart` — `LabTrackProvider extends ChangeNotifier`
- `lib/lab/demos/clock/widgets/clocks_tab.dart` — `ClocksTab` (existing grid + records + shake header)
- `lib/lab/demos/clock/widgets/tracks_tab.dart` — `TracksTab`
- `lib/lab/demos/clock/widgets/dashboard_tab.dart` — `DashboardTab`
- `lib/lab/demos/clock/widgets/track_editor_page.dart` — `TrackEditorPage`
- `lib/lab/demos/clock/widgets/track_runner_page.dart` — `TrackRunnerPage`
- `lib/lab/demos/clock/widgets/track_records_page.dart` — `TrackRecordsPage`
- `lib/lab/demos/clock/widgets/clock_editor_sheet.dart` — `ClockEditorSheet` (extracted from current `_showClockEditor`)
- `lib/lab/demos/clock/widgets/zen_theme.dart` — shared Zen palette + text styles
- `test/lab/demos/clock/lab_clock_v2_test.dart` — LabClock v2 round-trip
- `test/lab/demos/clock/lab_track_test.dart` — LabTrack round-trip
- `test/lab/demos/clock/lab_track_record_test.dart` — LabTrackRecord round-trip
- `test/lab/demos/clock/beat_coordinator_test.dart` — BeatCoordinator ownership arbitration
- `test/lab/demos/clock/lab_clock_provider_beat_test.dart` — startCountdown w/ beat triggers MetronomeFFI (mocked)
- `test/lab/demos/clock/lab_track_provider_test.dart` — track snapshot, segment advance
- `.tool/clock-redesign-lottery/feature-inventory.md` — feature preservation doc

**Modify:**
- `lib/lab/demos/clock/models/lab_clock.dart` — add `bpm` + `beatPattern` fields, `copyWith`, JsonSerializable
- `lib/lab/demos/clock/models/lab_clock.g.dart` — regenerated by build_runner
- `lib/lab/demos/clock/providers/lab_clock_provider.dart` — drop vibration, switch to `lab_clocks_v2`, hook `BeatCoordinator`
- `lib/lab/demos/clock_demo.dart` — replace 1756-line monolith with tab shell + thin entry

**Reuse (no change):**
- `lib/lab/demos/metronome/ffi_bindings.dart` — `MetronomeFFI` is the FFI surface
- `lib/lab/demos/metronome/const_metronome.dart` — `MetronomePresets.patterns`
- `lib/lab/demos/clock/utils/clock_color_util.dart` — overflow color
- `lib/native/home_widget/clock_widget_service.dart` — same `ClockWidgetData` shape

---

## Task 1: Feature inventory doc

**Files:**
- Create: `.tool/clock-redesign-lottery/feature-inventory.md`

**Interfaces:** None.

- [ ] **Step 1: Write the feature inventory doc**

Write a markdown file enumerating every existing feature in the current Clock demo with file path + line range. Use this exact content (one section per feature):

```markdown
# Clock Demo — Feature Inventory (2026-07-28)

This is a snapshot of every user-facing feature in the current Clock demo,
before the Track/Beat restructuring. Anything missing here is **not** preserved by the new code.

## Clock grid
- 2-column grid of clock cards (`lib/lab/demos/clock_demo.dart:482-518`).
- Card displays title, optional description, large remaining time, color, play/pause + reset controls (`lib/lab/demos/clock_demo.dart:1573-1724`).
- Tap card → edit sheet (`lib/lab/demos/clock_demo.dart:798-800`).
- Card color deepens as countdown overruns (negative remaining) (`lib/lab/demos/clock/utils/clock_color_util.dart`).
- "×" close icon on each card opens delete confirmation (`lib/lab/demos/clock_demo.dart:802-823`).
- "+" FAB opens the editor for a new clock (`lib/lab/demos/clock_demo.dart:794-796`).

## Countdown behavior
- Each clock ticks per-second via `LabClockProvider._startTimer` (`lib/lab/demos/clock/providers/lab_clock_provider.dart:69-101`).
- Overflow: `remainingSeconds` can go negative; UI displays `-HH:MM:SS` (`lib/lab/demos/clock_demo.dart:1715-1723`).
- When `remainingSeconds` crosses 0 from positive, vibrate 3s + ring (`lib/lab/demos/clock/providers/lab_clock_provider.dart:84-87` and `103-145`).
- Pause / resume / reset persist via `startTime` + `startRemainingSeconds` snapshot (`lib/lab/demos/clock/providers/lab_clock_provider.dart:262-346`).
- On `AppLifecycleState.resumed`, re-derive `remainingSeconds` from `startTime` (`lib/lab/demos/clock/providers/lab_clock_provider.dart:33-67`).
- "Shake to start" listens to `accelerometerEventStream`, finds the first non-running clock, and starts it (`lib/lab/demos/clock_demo.dart:154-260`). Persisted via `shake_to_start_enabled` SharedPreferences key.
- Home screen widget syncs the first clock's title, remaining, color, and isRunning (`lib/lab/demos/clock/providers/lab_clock_provider.dart:147-169` → `ClockWidgetService`).

## Clock editor sheet
- Title + description text fields (`lib/lab/demos/clock_demo.dart:961-976`).
- H:M:S wheel pickers (`lib/lab/demos/clock_demo.dart:1108-1156`).
- 8-color picker with selected ring (`lib/lab/demos/clock_demo.dart:913-922, 1024-1055`).
- Save / Add button writes through provider and dismisses (`lib/lab/demos/clock_demo.dart:1057-1098`).

## Record list (bottom of main page)
- Vertical list of `LabClockRecord` entries (`lib/lab/demos/clock_demo.dart:660-792`).
- Each row: leading icon (✓ green if completed, ⏰ amber if running), title, subtitle (date + planned duration), trailing actual-duration pill.
- Long-press title → rename dialog (`lib/lab/demos/clock_demo.dart:825-863`).
- Swipe left → exposes "Create" (creates a new clock using actual duration) and "Delete" actions (`lib/lab/demos/clock_demo.dart:1396-1570`).
- "Clear" button in the records header → confirm dialog (`lib/lab/demos/clock_demo.dart:865-886`).

## Persistence
- `LabClock` and `LabClockRecord` are saved to `SharedPreferences` keys `'lab_clocks'` and `'lab_clock_records'` (`lib/lab/demos/clock/providers/lab_clock_provider.dart:17-18, 196-210`).
- `loadClocks` is called from the provider constructor AND from `clock_demo.dart initState` (double-load, defensive) (`lib/lab/demos/clock/providers/lab_clock_provider.dart:30` and `lib/lab/demos/clock_demo.dart:92-95`).

## Wave divider
- A draggable horizontal line splits the clock grid (top) from the record list (bottom) (`lib/lab/demos/clock_demo.dart:323-480`).
- The line "breathes" when any clock is running, animates to flat when stopped (`lib/lab/demos/clock_demo.dart:1162-1393`).
- Snap points at 30% / 50% / 70% with `easeOutBack` animation (`lib/lab/demos/clock_demo.dart:262-321`).
- A pill handle sits above the wave (`lib/lab/demos/clock_demo.dart:420-437`).
- A tooltip "向下拖动波浪线查看记录" appears when the divider is near 0% (`lib/lab/demos/clock_demo.dart:447-473`).

## Behaviors to be **dropped** in v2
- All `HapticFeedback` / `_vibrate*` / `audioplayers` / `MethodChannel('io.github.xiaodouzi.fr/clock')` references — replaced by metronome tick.
- The wave divider and its breathing animation — replaced by a bottom Tab Bar.
- Old `lab_clocks` JSON loading — replaced by `lab_clocks_v2`.
```

- [ ] **Step 2: Verify file is created**

Run: `ls -la ".tool/clock-redesign-lottery/feature-inventory.md"`
Expected: file exists, size > 2 KB.

- [ ] **Step 3: Commit**

```bash
git add ".tool/clock-redesign-lottery/feature-inventory.md"
git commit -m "docs: snapshot current clock features before restructure"
```

---

## Task 2: Add bpm + beatPattern to LabClock model

**Files:**
- Modify: `lib/lab/demos/clock/models/lab_clock.dart`
- Regenerate: `lib/lab/demos/clock/models/lab_clock.g.dart`
- Create: `test/lab/demos/clock/lab_clock_v2_test.dart`

**Interfaces:**
- Produces: `LabClock({...existing, bpm: int? = null, beatPattern: String? = null})` and matching `copyWith` + JSON.

- [ ] **Step 1: Write the failing test**

Create `test/lab/demos/clock/lab_clock_v2_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';

void main() {
  group('LabClock v2 round-trip', () {
    test('default ctor leaves beat fields null', () {
      final c = LabClock(
        id: 'a',
        title: 'Quick Stretch',
        createdAt: DateTime.utc(2026, 7, 28, 10, 0),
      );
      expect(c.bpm, isNull);
      expect(c.beatPattern, isNull);
    });

    test('copyWith preserves beat fields when not overridden', () {
      final c = LabClock(
        id: 'a',
        title: 't',
        createdAt: DateTime.utc(2026, 7, 28),
        bpm: 60,
        beatPattern: '4/4',
      );
      final c2 = c.copyWith(title: 't2');
      expect(c2.bpm, 60);
      expect(c2.beatPattern, '4/4');
    });

    test('JSON round-trip preserves beat fields', () {
      final c = LabClock(
        id: 'a',
        title: 't',
        createdAt: DateTime.utc(2026, 7, 28),
        bpm: 90,
        beatPattern: '3/4',
      );
      final j = c.toJson();
      final c2 = LabClock.fromJson(j);
      expect(c2.bpm, 90);
      expect(c2.beatPattern, '3/4');
    });

    test('legacy JSON without beat fields loads as null', () {
      final j = {
        'id': 'a',
        'title': 't',
        'description': '',
        'createdAt': '2026-07-28T10:00:00.000Z',
        'isRunning': false,
        'remainingSeconds': 60,
      };
      final c = LabClock.fromJson(j);
      expect(c.bpm, isNull);
      expect(c.beatPattern, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/lab/demos/clock/lab_clock_v2_test.dart`
Expected: FAIL — `bpm` getter not found (compile error).

- [ ] **Step 3: Add fields + copyWith to LabClock**

Modify `lib/lab/demos/clock/models/lab_clock.dart`. Add two nullable fields after `startRemainingSeconds`:

```dart
  final int? bpm;          // 20..300, null = no beat
  final String? beatPattern; // key into MetronomePresets.patterns, null = no beat
```

Add to constructor params (with default `null`):

```dart
    this.bpm,
    this.beatPattern,
```

Add to `copyWith` params + body:

```dart
    int? bpm,
    String? beatPattern,
  }) {
    return LabClock(
      // ... existing fields ...
      bpm: bpm ?? this.bpm,
      beatPattern: beatPattern ?? this.beatPattern,
    );
  }
```

- [ ] **Step 4: Regenerate lab_clock.g.dart**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `lab_clock.g.dart` regenerated with `bpm` / `beatPattern` in `_$LabClockFromJson` / `_$LabClockToJson`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/lab/demos/clock/lab_clock_v2_test.dart`
Expected: 4/4 pass.

- [ ] **Step 6: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/`
Expected: 0 errors.

- [ ] **Step 7: Commit**

```bash
git add lib/lab/demos/clock/models/lab_clock.dart \
        lib/lab/demos/clock/models/lab_clock.g.dart \
        test/lab/demos/clock/lab_clock_v2_test.dart
git commit -m "feat(clock): add bpm + beatPattern fields to LabClock"
```

---

## Task 3: New LabTrack + LabTrackSegment model

**Files:**
- Create: `lib/lab/demos/clock/models/lab_track.dart`
- Create: `lib/lab/demos/clock/models/lab_track.g.dart` (generated)
- Create: `test/lab/demos/clock/lab_track_test.dart`

**Interfaces:**
- Produces: `LabTrack` and `LabTrackSegment` JSON-serializable classes.

- [ ] **Step 1: Write the failing test**

Create `test/lab/demos/clock/lab_track_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track.dart';

void main() {
  group('LabTrack round-trip', () {
    test('empty segments list survives round-trip', () {
      final t = LabTrack(
        id: 'a',
        title: 'morning',
        createdAt: DateTime.utc(2026, 7, 28, 8, 0),
        segments: const [],
      );
      final j = t.toJson();
      final t2 = LabTrack.fromJson(j);
      expect(t2.segments, isEmpty);
      expect(t2.title, 'morning');
    });

    test('segments snapshot clock metadata', () {
      final t = LabTrack(
        id: 'a',
        title: 'morning',
        createdAt: DateTime.utc(2026, 7, 28, 8, 0),
        segments: [
          LabTrackSegment(
            clockId: 'clk1',
            snapshotTitle: 'Warmup',
            snapshotColor: '#FF9500',
            snapshotDurationSeconds: 300,
            snapshotBpm: 60,
            snapshotBeatPattern: '4/4',
          ),
          LabTrackSegment(
            clockId: 'clk2',
            snapshotTitle: 'Work',
            snapshotDurationSeconds: 1500,
          ),
        ],
      );
      final j = t.toJson();
      final t2 = LabTrack.fromJson(j);
      expect(t2.segments.length, 2);
      expect(t2.segments[0].snapshotTitle, 'Warmup');
      expect(t2.segments[0].snapshotBpm, 60);
      expect(t2.segments[1].snapshotBpm, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/lab/demos/clock/lab_track_test.dart`
Expected: FAIL — `LabTrack` not defined.

- [ ] **Step 3: Implement LabTrack + LabTrackSegment**

Create `lib/lab/demos/clock/models/lab_track.dart`:

```dart
import 'package:json_annotation/json_annotation.dart';

part 'lab_track.g.dart';

@JsonSerializable()
class LabTrack {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final List<LabTrackSegment> segments;

  LabTrack({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    required this.segments,
  });

  factory LabTrack.fromJson(Map<String, dynamic> json) => _$LabTrackFromJson(json);
  Map<String, dynamic> toJson() => _$LabTrackToJson(this);

  LabTrack copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    List<LabTrackSegment>? segments,
  }) {
    return LabTrack(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      segments: segments ?? this.segments,
    );
  }
}

@JsonSerializable()
class LabTrackSegment {
  /// Reference to the source clock. May point to a deleted clock;
  /// track playback uses snapshot fields, not the live clock.
  final String clockId;

  /// Snapshotted at add-time so editing the original clock doesn't break the track.
  final String snapshotTitle;
  final String? snapshotColor;
  final int snapshotDurationSeconds;
  final int? snapshotBpm;
  final String? snapshotBeatPattern;

  LabTrackSegment({
    required this.clockId,
    required this.snapshotTitle,
    this.snapshotColor,
    required this.snapshotDurationSeconds,
    this.snapshotBpm,
    this.snapshotBeatPattern,
  });

  factory LabTrackSegment.fromJson(Map<String, dynamic> json) =>
      _$LabTrackSegmentFromJson(json);
  Map<String, dynamic> toJson() => _$LabTrackSegmentToJson(this);
}
```

- [ ] **Step 4: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `lab_track.g.dart` created.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/lab/demos/clock/lab_track_test.dart`
Expected: 2/2 pass.

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/clock/models/lab_track.dart \
        lib/lab/demos/clock/models/lab_track.g.dart \
        test/lab/demos/clock/lab_track_test.dart
git commit -m "feat(clock): add LabTrack + LabTrackSegment model"
```

---

## Task 4: New LabTrackRecord model

**Files:**
- Create: `lib/lab/demos/clock/models/lab_track_record.dart`
- Create: `lib/lab/demos/clock/models/lab_track_record.g.dart` (generated)
- Create: `test/lab/demos/clock/lab_track_record_test.dart`

**Interfaces:**
- Produces: `LabTrackRecord` JSON-serializable.

- [ ] **Step 1: Write the failing test**

Create `test/lab/demos/clock/lab_track_record_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track_record.dart';

void main() {
  group('LabTrackRecord round-trip', () {
    test('in-progress record defaults to non-completed', () {
      final r = LabTrackRecord(
        id: 'a',
        trackId: 't',
        trackTitle: 'morning',
        startTime: DateTime.utc(2026, 7, 28, 8, 0),
        totalDurationSeconds: 1800,
        segmentIndex: 0,
        perSegmentSeconds: const [300, 1500],
      );
      final j = r.toJson();
      final r2 = LabTrackRecord.fromJson(j);
      expect(r2.completed, isFalse);
      expect(r2.endTime, isNull);
      expect(r2.segmentIndex, 0);
      expect(r2.perSegmentSeconds, [300, 1500]);
    });

    test('completed record carries accumulated seconds', () {
      final r = LabTrackRecord(
        id: 'a',
        trackId: 't',
        trackTitle: 'morning',
        startTime: DateTime.utc(2026, 7, 28, 8, 0),
        endTime: DateTime.utc(2026, 7, 28, 8, 30),
        totalDurationSeconds: 1800,
        completed: true,
        accumulatedSeconds: 1820,
        segmentIndex: 2,
        perSegmentSeconds: const [300, 1500, 20],
      );
      final j = r.toJson();
      final r2 = LabTrackRecord.fromJson(j);
      expect(r2.completed, isTrue);
      expect(r2.accumulatedSeconds, 1820);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/lab/demos/clock/lab_track_record_test.dart`
Expected: FAIL — `LabTrackRecord` not defined.

- [ ] **Step 3: Implement LabTrackRecord**

Create `lib/lab/demos/clock/models/lab_track_record.dart`:

```dart
import 'package:json_annotation/json_annotation.dart';

part 'lab_track_record.g.dart';

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
  final int segmentIndex;            // last fully completed segment
  final List<int> perSegmentSeconds; // actual elapsed per segment

  LabTrackRecord({
    required this.id,
    required this.trackId,
    required this.trackTitle,
    this.customTitle,
    required this.startTime,
    this.endTime,
    required this.totalDurationSeconds,
    this.completed = false,
    this.accumulatedSeconds,
    required this.segmentIndex,
    required this.perSegmentSeconds,
  });

  factory LabTrackRecord.fromJson(Map<String, dynamic> json) =>
      _$LabTrackRecordFromJson(json);
  Map<String, dynamic> toJson() => _$LabTrackRecordToJson(this);

  LabTrackRecord copyWith({
    String? id,
    String? trackId,
    String? trackTitle,
    String? customTitle,
    DateTime? startTime,
    DateTime? endTime,
    int? totalDurationSeconds,
    bool? completed,
    int? accumulatedSeconds,
    int? segmentIndex,
    List<int>? perSegmentSeconds,
  }) {
    return LabTrackRecord(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      trackTitle: trackTitle ?? this.trackTitle,
      customTitle: customTitle ?? this.customTitle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      completed: completed ?? this.completed,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      segmentIndex: segmentIndex ?? this.segmentIndex,
      perSegmentSeconds: perSegmentSeconds ?? this.perSegmentSeconds,
    );
  }
}
```

- [ ] **Step 4: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `lab_track_record.g.dart` created.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/lab/demos/clock/lab_track_record_test.dart`
Expected: 2/2 pass.

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/clock/models/lab_track_record.dart \
        lib/lab/demos/clock/models/lab_track_record.g.dart \
        test/lab/demos/clock/lab_track_record_test.dart
git commit -m "feat(clock): add LabTrackRecord model"
```

---

## Task 5: BeatCoordinator (singleton owner of MetronomeFFI)

**Files:**
- Create: `lib/lab/demos/clock/providers/beat_coordinator.dart`
- Create: `test/lab/demos/clock/beat_coordinator_test.dart`

**Interfaces:**
- Produces:
  - `BeatCoordinator.requestOwnership({required String providerId, int? bpm, String? beatPattern})` — returns true if granted.
  - `BeatCoordinator.releaseOwnership(String providerId)` — no-op if not owner.
  - `BeatCoordinator.ownerId` — getter.
  - `BeatCoordinator.registerBeatenOutCallback(ValueChanged<String> cb)` — invoked when another provider steals ownership.
  - `BeatCoordinator.resetForTest()` — clears all state (test-only).

Note: `MetronomeFFI` is not directly mockable in Dart tests because it's a real FFI. The test exercises only the ownership arbitration logic. The real `MetronomeFFI` calls inside the implementation are guarded by `// ignore: invalid_use_of_protected_member`-style patterns and are wrapped in a single internal helper that tests can verify by stubbing the singleton's internal callback list.

**Design simplification for testability**: The coordinator delegates FFI calls to an internal `BeatSink` interface. The default sink calls `MetronomeFFI`; tests use a fake `BeatSink` that records calls.

- [ ] **Step 1: Write the failing test**

Create `test/lab/demos/clock/beat_coordinator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/beat_coordinator.dart';

void main() {
  setUp(BeatCoordinator.resetForTest);
  tearDown(BeatCoordinator.resetForTest);

  group('BeatCoordinator', () {
    test('first request is granted', () {
      final granted = BeatCoordinator.requestOwnership(
        providerId: 'clock:a',
        bpm: 60,
        beatPattern: '4/4',
      );
      expect(granted, isTrue);
      expect(BeatCoordinator.ownerId, 'clock:a');
    });

    test('second request from a different provider steals ownership', () {
      BeatCoordinator.requestOwnership(providerId: 'clock:a', bpm: 60, beatPattern: '4/4');
      String? stolenFrom;
      BeatCoordinator.registerBeatenOutCallback((id) => stolenFrom = id);

      BeatCoordinator.requestOwnership(providerId: 'track:t', bpm: 80, beatPattern: '3/4');

      expect(BeatCoordinator.ownerId, 'track:t');
      expect(stolenFrom, 'clock:a');
    });

    test('release by current owner clears owner', () {
      BeatCoordinator.requestOwnership(providerId: 'clock:a', bpm: 60, beatPattern: '4/4');
      BeatCoordinator.releaseOwnership('clock:a');
      expect(BeatCoordinator.ownerId, isNull);
    });

    test('release by non-owner is a no-op', () {
      BeatCoordinator.requestOwnership(providerId: 'clock:a', bpm: 60, beatPattern: '4/4');
      BeatCoordinator.releaseOwnership('clock:b');
      expect(BeatCoordinator.ownerId, 'clock:a');
    });

    test('null bpm/pattern still records ownership', () {
      BeatCoordinator.requestOwnership(providerId: 'clock:a');
      expect(BeatCoordinator.ownerId, 'clock:a');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/lab/demos/clock/beat_coordinator_test.dart`
Expected: FAIL — `BeatCoordinator` not defined.

- [ ] **Step 3: Implement BeatCoordinator with a BeatSink interface**

Create `lib/lab/demos/clock/providers/beat_coordinator.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/const_metronome.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/ffi_bindings.dart';

/// Internal sink so tests can replace the FFI surface.
abstract class BeatSink {
  void setBpm(double bpm);
  void setBeatsPerBar(int n);
  void setBeatAccentLevel(int idx, int level); // 0=weak, 1=medium, 2=accent
  void play();
  void pause();
}

class _OboeBeatSink implements BeatSink {
  @override
  void setBpm(double bpm) => MetronomeFFI.setBpm(bpm);
  @override
  void setBeatsPerBar(int n) => MetronomeFFI.setBeatsPerBar(n);
  @override
  void setBeatAccentLevel(int idx, int level) => MetronomeFFI.setBeatAccentLevel(idx, level);
  @override
  void play() => MetronomeFFI.play();
  @override
  void pause() => MetronomeFFI.pause();
}

/// Single owner of the Oboe audio stream. Both `LabClockProvider` and
/// `LabTrackProvider` must call [requestOwnership] before issuing FFI commands
/// and [releaseOwnership] when their entity stops. If another provider steals
/// ownership, the previous owner's `beatenOutCallback` fires.
class BeatCoordinator {
  static String? _ownerId;
  static ValueChanged<String>? _onBeatenOut;
  static BeatSink _sink = _OboeBeatSink();

  static String? get ownerId => _ownerId;

  /// Test-only: replace the FFI sink.
  static void setSinkForTest(BeatSink sink) => _sink = sink;

  /// Test-only: clear all coordinator state.
  static void resetForTest() {
    _ownerId = null;
    _onBeatenOut = null;
    _sink = _OboeBeatSink();
  }

  /// Request exclusive control of the metronome. Returns true if granted.
  /// If [bpm] / [beatPattern] are non-null, configures the audio stream
  /// before starting playback.
  static bool requestOwnership({
    required String providerId,
    int? bpm,
    String? beatPattern,
  }) {
    if (_ownerId != null && _ownerId != providerId) {
      final stolen = _ownerId!;
      _onBeatenOut?.call(stolen);
    }
    _ownerId = providerId;
    if (bpm != null) {
      _sink.setBpm(bpm.toDouble().clamp(20.0, 300.0));
    }
    if (beatPattern != null) {
      final pattern = MetronomePresets.patterns[beatPattern];
      if (pattern != null) {
        _sink.setBeatsPerBar(pattern.beatsPerMeasure);
        for (var i = 0; i < pattern.beatsPerMeasure; i++) {
          final isAccent = pattern.accentIndices.contains(i);
          _sink.setBeatAccentLevel(i, isAccent ? 2 : 0);
        }
      }
    }
    _sink.play();
    return true;
  }

  /// Release ownership. No-op if [providerId] is not the current owner.
  static void releaseOwnership(String providerId) {
    if (_ownerId != providerId) return;
    _ownerId = null;
    _sink.pause();
  }

  /// Register a callback fired when this provider's ownership is stolen.
  static void registerBeatenOutCallback(ValueChanged<String> cb) {
    _onBeatenOut = cb;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/lab/demos/clock/beat_coordinator_test.dart`
Expected: 5/5 pass.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/providers/beat_coordinator.dart`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/clock/providers/beat_coordinator.dart \
        test/lab/demos/clock/beat_coordinator_test.dart
git commit -m "feat(clock): add BeatCoordinator singleton owner of MetronomeFFI"
```

---

## Task 6: Modify LabClockProvider — drop vibration, switch to v2 key, hook beat

**Files:**
- Modify: `lib/lab/demos/clock/providers/lab_clock_provider.dart`
- Create: `test/lab/demos/clock/lab_clock_provider_beat_test.dart`

**Interfaces:**
- Produces: `LabClockProvider` with new methods:
  - `setBeat(String clockId, {int? bpm, String? beatPattern})`
  - `clearBeat(String clockId)`
  - `String? get activeBeatClockId` (read-only; returns `BeatCoordinator.ownerId` filtered to `clock:*` prefix)
- Storage: `'lab_clocks_v2'` / `'lab_clock_records_v2'`.
- Removes: `audioplayers` import, `AudioPlayer` field, `_playNotificationSound`, `_vibrate`, `_vibrate3Seconds`, the `MethodChannel('io.github.xiaodouzi.fr/clock')`, the `HapticFeedback` import.

- [ ] **Step 1: Write the failing test**

Create `test/lab/demos/clock/lab_clock_provider_beat_test.dart`:

```dart
import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/beat_coordinator.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_clock_provider.dart';

class _RecordingSink implements BeatSink {
  final List<String> events = [];
  @override
  void setBpm(double bpm) => events.add('setBpm:$bpm');
  @override
  void setBeatsPerBar(int n) => events.add('beatsPerBar:$n');
  @override
  void setBeatAccentLevel(int idx, int level) => events.add('accent:$idx:$level');
  @override
  void play() => events.add('play');
  @override
  void pause() => events.add('pause');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BeatCoordinator.resetForTest();
  });
  tearDown(BeatCoordinator.resetForTest);

  test('startCountdown on a beat-clock requests ownership', () async {
    final sink = _RecordingSink();
    BeatCoordinator.setSinkForTest(sink);
    final p = LabClockProvider()..loadClocks();
    final c = await p.createClock(title: 'warmup', durationSeconds: 60);
    await p.setBeat(c.id, bpm: 60, beatPattern: '4/4');

    await p.startCountdown(c.id);

    expect(sink.events, contains('setBpm:60.0'));
    expect(sink.events, contains('beatsPerBar:4'));
    expect(sink.events, contains('play'));
    expect(BeatCoordinator.ownerId, 'clock:${c.id}');
  });

  test('pauseCountdown releases ownership', () async {
    final sink = _RecordingSink();
    BeatCoordinator.setSinkForTest(sink);
    final p = LabClockProvider()..loadClocks();
    final c = await p.createClock(title: 't', durationSeconds: 60);
    await p.setBeat(c.id, bpm: 60, beatPattern: '4/4');
    await p.startCountdown(c.id);
    sink.events.clear();

    await p.pauseCountdown(c.id);

    expect(sink.events, contains('pause'));
    expect(BeatCoordinator.ownerId, isNull);
  });

  test('clearBeat stops ongoing beat', () async {
    final sink = _RecordingSink();
    BeatCoordinator.setSinkForTest(sink);
    final p = LabClockProvider()..loadClocks();
    final c = await p.createClock(title: 't', durationSeconds: 60);
    await p.setBeat(c.id, bpm: 60, beatPattern: '4/4');
    await p.startCountdown(c.id);
    sink.events.clear();

    await p.clearBeat(c.id);

    expect(sink.events, contains('pause'));
  });

  test('clock without bpm does not request ownership', () async {
    final sink = _RecordingSink();
    BeatCoordinator.setSinkForTest(sink);
    final p = LabClockProvider()..loadClocks();
    final c = await p.createClock(title: 't', durationSeconds: 60);
    await p.startCountdown(c.id);
    expect(sink.events.any((e) => e == 'play'), isFalse);
    expect(BeatCoordinator.ownerId, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/lab/demos/clock/lab_clock_provider_beat_test.dart`
Expected: FAIL — `setBeat` / `clearBeat` not defined.

- [ ] **Step 3: Modify LabClockProvider**

Edit `lib/lab/demos/clock/providers/lab_clock_provider.dart`. Apply these changes in order:

1. **Remove imports** for `audioplayers`, `flutter/services.dart`, and the `MethodChannel` constant.

2. **Remove fields**:
   - `final AudioPlayer _audioPlayer = AudioPlayer();`
   - `static const _soundChannel = MethodChannel('io.github.xiaodouzi.fr/clock');`
   - `String? _activeBeatClockId;` (no — moved to BeatCoordinator).

3. **Add import**:
   ```dart
   import 'beat_coordinator.dart';
   ```

4. **Switch storage keys**:
   ```dart
   static const String _storageKey = 'lab_clocks_v2';
   static const String _recordsKey = 'lab_clock_records_v2';
   ```

5. **Add public beat methods** (place after `clearRecords`):
   ```dart
   /// Configure the BPM and pattern for a clock. Pass nulls to clear.
   Future<void> setBeat(String clockId, {int? bpm, String? beatPattern}) async {
     final i = _clocks.indexWhere((c) => c.id == clockId);
     if (i == -1) return;
     _clocks[i] = _clocks[i].copyWith(bpm: bpm, beatPattern: beatPattern);
     await _saveClocks();
     _syncToWidget();
     notifyListeners();
   }

   /// Remove beat config from a clock and stop its metronome.
   Future<void> clearBeat(String clockId) async {
     await setBeat(clockId, bpm: null, beatPattern: null);
     if (_clocks.firstWhere((c) => c.id == clockId, orElse: () => _clocks.first).isRunning) {
       BeatCoordinator.releaseOwnership('clock:$clockId');
     }
   }

   /// The id of the clock currently driving the metronome, or null.
   String? get activeBeatClockId {
     final owner = BeatCoordinator.ownerId;
     if (owner == null) return null;
     if (!owner.startsWith('clock:')) return null;
     return owner.substring('clock:'.length);
   }
   ```

6. **Hook into `startCountdown`** — at the end (after `_saveClocks()`), add:
   ```dart
   final c2 = _clocks[i];
   if (c2.bpm != null) {
     BeatCoordinator.requestOwnership(
       providerId: 'clock:$id',
       bpm: c2.bpm,
       beatPattern: c2.beatPattern,
     );
   }
   ```

7. **Hook into `pauseCountdown`** — at the end:
   ```dart
   BeatCoordinator.releaseOwnership('clock:$id');
   ```

8. **Hook into `resetCountdown`** — at the end:
   ```dart
   BeatCoordinator.releaseOwnership('clock:$id');
   ```

9. **Remove** the entire `_vibrate3Seconds` / `_playNotificationSound` / `_vibrate` methods (lines 103-145 in the current file).

10. **Remove the vibration trigger** in `_startTimer`:
    ```dart
    // DELETE these 4 lines:
    if (clock.remainingSeconds > 0 && newRemaining <= 0) {
      _vibrate3Seconds();
    }
    ```

11. **Remove `_audioPlayer.dispose()`** from `dispose` and the `AudioPlayer` field.

12. **Register the beaten-out callback in the constructor**:
    ```dart
    BeatCoordinator.registerBeatenOutCallback((id) {
      if (id.startsWith('clock:')) {
        // Mark clock as beatSilent so the UI can grey out the dot.
        // We don't notifyListeners here because the per-second Timer
        // already rebuilds cards every tick; we just track the flag.
        // Implementation: store in a private set; UI reads via getter.
      }
    });
    ```

    Concretely, add:
    ```dart
    final Set<String> _silencedClocks = {};
    bool isClockSilenced(String clockId) => _silencedClocks.contains(clockId);

    // In the callback body:
    if (id.startsWith('clock:')) {
      _silencedClocks.add(id.substring('clock:'.length));
      notifyListeners();
    }
    ```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/lab/demos/clock/lab_clock_provider_beat_test.dart`
Expected: 4/4 pass.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/providers/`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/clock/providers/lab_clock_provider.dart \
        test/lab/demos/clock/lab_clock_provider_beat_test.dart
git commit -m "refactor(clock): drop vibration, switch to v2 key, hook BeatCoordinator"
```

---

## Task 7: New LabTrackProvider

**Files:**
- Create: `lib/lab/demos/clock/providers/lab_track_provider.dart`
- Create: `test/lab/demos/clock/lab_track_provider_test.dart`

**Interfaces:**
- Produces:
  - `LabTrackProvider extends ChangeNotifier` with `loadTracks`, `createTrack`, `updateTrack`, `deleteTrack`, `startTrack(trackId)`, `pauseTrack()`, `skipSegment()`, `stopTrack()`, `getRecordLiveDuration(record)`.
  - Storage keys: `'lab_tracks'`, `'lab_track_records'`.

- [ ] **Step 1: Write the failing test**

Create `test/lab/demos/clock/lab_track_provider_test.dart`:

```dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track_record.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/beat_coordinator.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/providers/lab_track_provider.dart';

class _RecordingSink implements BeatSink {
  final List<String> events = [];
  @override void setBpm(double bpm) => events.add('setBpm:$bpm');
  @override void setBeatsPerBar(int n) => events.add('beatsPerBar:$n');
  @override void setBeatAccentLevel(int idx, int level) => events.add('accent:$idx:$level');
  @override void play() => events.add('play');
  @override void pause() => events.add('pause');
}

LabTrack _track() => LabTrack(
  id: 't1',
  title: 'morning',
  createdAt: DateTime.utc(2026, 7, 28),
  segments: const [
    LabTrackSegment(
      clockId: 'c1', snapshotTitle: 'A',
      snapshotColor: '#FF9500', snapshotDurationSeconds: 60,
      snapshotBpm: 60, snapshotBeatPattern: '4/4',
    ),
    LabTrackSegment(
      clockId: 'c2', snapshotTitle: 'B',
      snapshotDurationSeconds: 120,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    BeatCoordinator.resetForTest();
  });
  tearDown(BeatCoordinator.resetForTest);

  test('startTrack snapshots segment data and creates a record', () async {
    final sink = _RecordingSink();
    BeatCoordinator.setSinkForTest(sink);
    final p = LabTrackProvider();
    await p.createTrack(_track());

    await p.startTrack('t1');

    expect(p.activeTrackId, 't1');
    expect(p.currentSegmentIndex, 0);
    expect(p.records.length, 1);
    expect(p.records.first.completed, isFalse);
    expect(sink.events, contains('setBpm:60.0'));
    expect(sink.events, contains('beatsPerBar:4'));
    expect(sink.events, contains('play'));
    expect(BeatCoordinator.ownerId, 'track:t1');
  });

  test('skipSegment advances to next segment', () async {
    final sink = _RecordingSink();
    BeatCoordinator.setSinkForTest(sink);
    final p = LabTrackProvider();
    await p.createTrack(_track());
    await p.startTrack('t1');

    await p.skipSegment();

    expect(p.currentSegmentIndex, 1);
    // Second segment has no bpm, so bpm/pattern commands should NOT be issued.
    sink.events.clear();
    await p.skipSegment();
    expect(sink.events.any((e) => e.startsWith('setBpm')), isFalse);
    expect(p.currentSegmentIndex, 2); // past end
  });

  test('stopTrack completes record and releases ownership', () async {
    final sink = _RecordingSink();
    BeatCoordinator.setSinkForTest(sink);
    final p = LabTrackProvider();
    await p.createTrack(_track());
    await p.startTrack('t1');

    await p.stopTrack();

    expect(p.activeTrackId, isNull);
    expect(BeatCoordinator.ownerId, isNull);
    final rec = p.records.first;
    expect(rec.completed, isTrue);
    expect(rec.accumulatedSeconds, isNotNull);
  });

  test('deleteTrack removes the track and its records', () async {
    final p = LabTrackProvider();
    await p.createTrack(_track());
    await p.deleteTrack('t1');
    expect(p.tracks, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/lab/demos/clock/lab_track_provider_test.dart`
Expected: FAIL — `LabTrackProvider` not defined.

- [ ] **Step 3: Implement LabTrackProvider**

Create `lib/lab/demos/clock/providers/lab_track_provider.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_track_record.dart';
import 'beat_coordinator.dart';

class LabTrackProvider with ChangeNotifier {
  List<LabTrack> _tracks = [];
  List<LabTrackRecord> _records = [];
  static const String _tracksKey = 'lab_tracks';
  static const String _recordsKey = 'lab_track_records';

  // Runtime state
  String? _activeTrackId;
  int _currentSegmentIndex = 0;
  DateTime? _segmentStartTime;
  int _segmentStartRemaining = 0;
  Timer? _timer;

  // Public getters
  List<LabTrack> get tracks => _tracks;
  List<LabTrackRecord> get records => _records;
  String? get activeTrackId => _activeTrackId;
  int get currentSegmentIndex => _currentSegmentIndex;

  LabTrackProvider() {
    BeatCoordinator.registerBeatenOutCallback((id) {
      if (id.startsWith('track:')) {
        // Mark this track as beat-silent; the per-second tick still updates UI.
        // For now, we just notify listeners so the runner dot can grey out.
        notifyListeners();
      }
    });
  }

  Future<void> loadTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final tracksJson = prefs.getString(_tracksKey);
    if (tracksJson != null) {
      _tracks = (json.decode(tracksJson) as List)
          .map((e) => LabTrack.fromJson(e))
          .toList();
    }
    final recordsJson = prefs.getString(_recordsKey);
    if (recordsJson != null) {
      _records = (json.decode(recordsJson) as List)
          .map((e) => LabTrackRecord.fromJson(e))
          .toList();
      _records.sort((a, b) => b.startTime.compareTo(a.startTime));
    }
    notifyListeners();
  }

  Future<void> _saveTracks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tracksKey, json.encode(_tracks.map((e) => e.toJson()).toList()));
  }

  Future<void> _saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recordsKey, json.encode(_records.map((e) => e.toJson()).toList()));
  }

  Future<LabTrack> createTrack(LabTrack t) async {
    _tracks.insert(0, t);
    await _saveTracks();
    notifyListeners();
    return t;
  }

  Future<void> updateTrack(LabTrack t) async {
    final i = _tracks.indexWhere((x) => x.id == t.id);
    if (i == -1) return;
    _tracks[i] = t;
    await _saveTracks();
    notifyListeners();
  }

  Future<void> deleteTrack(String id) async {
    _tracks.removeWhere((t) => t.id == id);
    _records.removeWhere((r) => r.trackId == id);
    await _saveTracks();
    await _saveRecords();
    notifyListeners();
  }

  Future<void> startTrack(String trackId) async {
    final i = _tracks.indexWhere((t) => t.id == trackId);
    if (i == -1) return;
    final t = _tracks[i];
    if (t.segments.isEmpty) return;

    _activeTrackId = trackId;
    _currentSegmentIndex = 0;
    _segmentStartTime = DateTime.now();
    _segmentStartRemaining = t.segments[0].snapshotDurationSeconds;

    // Create the record (only if not already active).
    if (!_records.any((r) => r.trackId == trackId && r.endTime == null)) {
      final rec = LabTrackRecord(
        id: const Uuid().v4(),
        trackId: t.id,
        trackTitle: t.title,
        startTime: _segmentStartTime!,
        totalDurationSeconds: t.segments.fold(0, (s, seg) => s + seg.snapshotDurationSeconds),
        segmentIndex: 0,
        perSegmentSeconds: List.filled(t.segments.length, 0),
      );
      _records.insert(0, rec);
      await _saveRecords();
    }

    // Request beat ownership for the first segment.
    final seg = t.segments[0];
    if (seg.snapshotBpm != null) {
      BeatCoordinator.requestOwnership(
        providerId: 'track:$trackId',
        bpm: seg.snapshotBpm,
        beatPattern: seg.snapshotBeatPattern,
      );
    }

    _startTimer();
    await _saveTracks();
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeTrackId == null) return;
      final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
      if (i == -1) return;
      final t = _tracks[i];
      if (_currentSegmentIndex >= t.segments.length) return;
      final seg = t.segments[_currentSegmentIndex];
      final elapsed = DateTime.now().difference(_segmentStartTime!).inSeconds;
      final newRemaining = _segmentStartRemaining - elapsed;
      if (newRemaining <= 0) {
        _advanceSegment();
      }
      notifyListeners();
    });
  }

  void _advanceSegment() {
    if (_activeTrackId == null) return;
    final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
    if (i == -1) return;
    final t = _tracks[i];

    // Update the in-flight record with elapsed seconds for this segment.
    final recIdx = _records.indexWhere(
      (r) => r.trackId == _activeTrackId && r.endTime == null,
    );
    if (recIdx != -1) {
      final r = _records[recIdx];
      final newSeg = List<int>.from(r.perSegmentSeconds);
      final consumed = t.segments[_currentSegmentIndex].snapshotDurationSeconds -
          _segmentStartRemaining + 0; // already past
      newSeg[_currentSegmentIndex] = _segmentStartRemaining;
      _records[recIdx] = r.copyWith(segmentIndex: _currentSegmentIndex, perSegmentSeconds: newSeg);
    }

    _currentSegmentIndex += 1;
    if (_currentSegmentIndex >= t.segments.length) {
      _completeTrack();
      return;
    }
    final next = t.segments[_currentSegmentIndex];
    _segmentStartTime = DateTime.now();
    _segmentStartRemaining = next.snapshotDurationSeconds;
    if (next.snapshotBpm != null) {
      BeatCoordinator.requestOwnership(
        providerId: 'track:${_activeTrackId}',
        bpm: next.snapshotBpm,
        beatPattern: next.snapshotBeatPattern,
      );
    } else {
      BeatCoordinator.releaseOwnership('track:${_activeTrackId}');
    }
  }

  Future<void> _completeTrack() async {
    BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    final i = _tracks.indexWhere((t) => t.id == _activeTrackId);
    if (i == -1) return;
    final t = _tracks[i];
    final totalConsumed = t.segments.fold<int>(0, (s, seg) => s + seg.snapshotDurationSeconds);
    final recIdx = _records.indexWhere(
      (r) => r.trackId == _activeTrackId && r.endTime == null,
    );
    if (recIdx != -1) {
      _records[recIdx] = _records[recIdx].copyWith(
        endTime: DateTime.now(),
        completed: true,
        accumulatedSeconds: totalConsumed,
      );
      await _saveRecords();
    }
    _activeTrackId = null;
    _timer?.cancel();
    notifyListeners();
  }

  Future<void> pauseTrack() async {
    _timer?.cancel();
    BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    notifyListeners();
  }

  Future<void> skipSegment() async {
    _advanceSegment();
    notifyListeners();
  }

  Future<void> stopTrack() async {
    _timer?.cancel();
    BeatCoordinator.releaseOwnership('track:$_activeTrackId');
    // Mark record as stopped (not completed) so the user can see partial progress.
    final recIdx = _records.indexWhere(
      (r) => r.trackId == _activeTrackId && r.endTime == null,
    );
    if (recIdx != -1) {
      _records[recIdx] = _records[recIdx].copyWith(
        endTime: DateTime.now(),
        completed: false,
        accumulatedSeconds: 0,
      );
      await _saveRecords();
    }
    _activeTrackId = null;
    notifyListeners();
  }

  int getRecordLiveDuration(LabTrackRecord r) {
    if (r.completed) return r.accumulatedSeconds ?? 0;
    if (_activeTrackId == r.trackId && r.endTime == null) {
      // Approximate: sum of consumed segments so far.
      return r.perSegmentSeconds.take(r.segmentIndex + 1).fold(0, (a, b) => a + b);
    }
    return r.accumulatedSeconds ?? 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/lab/demos/clock/lab_track_provider_test.dart`
Expected: 4/4 pass.

- [ ] **Step 5: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/providers/`
Expected: 0 errors.

- [ ] **Step 6: Commit**

```bash
git add lib/lab/demos/clock/providers/lab_track_provider.dart \
        test/lab/demos/clock/lab_track_provider_test.dart
git commit -m "feat(clock): add LabTrackProvider with snapshot segments and beat"
```

---

## Task 8: Shared Zen theme + button styles

**Files:**
- Create: `lib/lab/demos/clock/widgets/zen_theme.dart`

**Interfaces:**
- Produces: `class ZenTheme` with `static const` colors and `static const TextStyle` for body / mono digits / button. Provides `ZenButtonStyle` and `ZenCardDecoration`.

- [ ] **Step 1: Implement ZenTheme**

Create `lib/lab/demos/clock/widgets/zen_theme.dart`:

```dart
import 'package:flutter/material.dart';

class ZenColors {
  static const bg = Color(0xFFF4F1EA);
  static const ink = Color(0xFF2C2C2C);
  static const hair = Color(0xFFD9D5C8);
  static const secondary = Color(0xFF8A8475);
  static const sage = Color(0xFF7A9A7E);
  static const mutedRed = Color(0xFFA0594A);
  static const surface = Color(0xFFFBF8F1);
}

class ZenText {
  static const body = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 16,
    color: ZenColors.ink,
    height: 1.3,
  );
  static const label = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 13,
    color: ZenColors.secondary,
  );
  static const title = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: ZenColors.ink,
  );
  static const button = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );
  static const monoDigit = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 40,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.ink,
  );
  static const monoDigitLarge = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 64,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.ink,
  );
  static const monoDigitSmall = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 14,
    fontFeatures: [FontFeature.tabularFigures()],
    color: ZenColors.secondary,
  );
}

BoxDecoration zenCard({Color? color}) => BoxDecoration(
      color: color ?? ZenColors.surface,
      border: Border.all(color: ZenColors.hair, width: 1),
      borderRadius: BorderRadius.circular(6),
    );

BoxDecoration zenDottedZone() => BoxDecoration(
      color: ZenColors.surface,
      border: Border.all(color: ZenColors.hair, width: 1, style: BorderStyle.solid),
      borderRadius: BorderRadius.circular(6),
    );

ButtonStyle zenButton({Color? foreground, Color? border, Color? background}) =>
    OutlinedButton.styleFrom(
      foregroundColor: foreground ?? ZenColors.ink,
      side: BorderSide(color: border ?? ZenColors.hair),
      backgroundColor: background,
      minimumSize: const Size(88, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: ZenText.button,
    );
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/widgets/zen_theme.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock/widgets/zen_theme.dart
git commit -m "feat(clock): add Zen theme tokens (palette, text styles, button style)"
```

---

## Task 9: Extract ClockEditorSheet from current _showClockEditor

**Files:**
- Create: `lib/lab/demos/clock/widgets/clock_editor_sheet.dart`

**Interfaces:**
- Produces: `Future<({String title, String description, int durationSeconds, String color, int? bpm, String? beatPattern})?> showClockEditor(BuildContext context, {LabClock? existing})` — returns `null` if cancelled.

- [ ] **Step 1: Implement ClockEditorSheet**

Create `lib/lab/demos/clock/widgets/clock_editor_sheet.dart` with the following content. The implementation ports the current `_showClockEditor` logic and adds the Beat section between Color and Save.

```dart
import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/lab/demos/clock/models/lab_clock.dart';
import 'package:xiaodouzi_fr/lab/demos/metronome/const_metronome.dart';
import 'zen_theme.dart';

class ClockEditorResult {
  final String title;
  final String description;
  final int durationSeconds;
  final String color;
  final int? bpm;
  final String? beatPattern;

  ClockEditorResult({
    required this.title,
    required this.description,
    required this.durationSeconds,
    required this.color,
    this.bpm,
    this.beatPattern,
  });
}

const _palette = [
  '#D4644B', '#7A9A7E', '#5B7A8C', '#C9A86A',
  '#A2808E', '#C7B299', '#5A544B', '#2C2C2C',
];

Future<ClockEditorResult?> showClockEditor(BuildContext context, {LabClock? existing}) {
  return showModalBottomSheet<ClockEditorResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: ZenColors.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ClockEditorSheet(existing: existing),
  );
}

class _ClockEditorSheet extends StatefulWidget {
  final LabClock? existing;
  const _ClockEditorSheet({this.existing});
  @override
  State<_ClockEditorSheet> createState() => _ClockEditorSheetState();
}

class _ClockEditorSheetState extends State<_ClockEditorSheet> {
  late TextEditingController _titleCtl;
  late TextEditingController _descCtl;
  late int _hours, _minutes, _seconds;
  late String _color;
  late bool _beatEnabled;
  late int _bpm;
  late String? _beatPattern;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _titleCtl = TextEditingController(text: c?.title ?? '');
    _descCtl = TextEditingController(text: c?.description ?? '');
    final total = c?.durationSeconds ?? 300;
    _hours = total ~/ 3600;
    _minutes = (total % 3600) ~/ 60;
    _seconds = total % 60;
    _color = c?.color ?? _palette.first;
    _beatEnabled = c?.bpm != null;
    _bpm = c?.bpm ?? 60;
    _beatPattern = c?.beatPattern ?? '4/4';
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _descCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(
              color: ZenColors.hair, borderRadius: BorderRadius.circular(2),
            ))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text(widget.existing == null ? 'Add clock' : 'Edit clock', style: ZenText.title)),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
                iconSize: 24,
                color: ZenColors.ink,
                tooltip: 'Cancel',
              ),
            ]),
            const SizedBox(height: 20),
            TextField(
              controller: _titleCtl,
              style: ZenText.body,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtl,
              style: ZenText.body,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Duration', style: ZenText.label),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _WheelPicker(label: 'h', value: _hours, max: 23, onChanged: (v) => setState(() => _hours = v)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(':', style: ZenText.title)),
                _WheelPicker(label: 'm', value: _minutes, max: 59, onChanged: (v) => setState(() => _minutes = v)),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(':', style: ZenText.title)),
                _WheelPicker(label: 's', value: _seconds, max: 59, onChanged: (v) => setState(() => _seconds = v)),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Color', style: ZenText.label),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _palette.map((c) {
                final selected = c == _color;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Color(int.parse(c.replaceFirst('#', '0xFF'))),
                      shape: BoxShape.circle,
                      border: selected ? Border.all(color: ZenColors.ink, width: 3) : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // Beat section
            Row(children: [
              const Expanded(child: Text('Beat', style: ZenText.label)),
              Switch(
                value: _beatEnabled,
                activeColor: ZenColors.sage,
                onChanged: (v) => setState(() => _beatEnabled = v),
              ),
            ]),
            if (_beatEnabled) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Text('BPM', style: ZenText.label),
                const Spacer(),
                IconButton(
                  onPressed: _bpm > 20 ? () => setState(() => _bpm -= 5) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 64,
                  child: Text('$_bpm', textAlign: TextAlign.center, style: ZenText.monoDigitSmall.copyWith(color: ZenColors.ink, fontSize: 20)),
                ),
                IconButton(
                  onPressed: _bpm < 300 ? () => setState(() => _bpm += 5) : null,
                  icon: const Icon(Icons.add),
                ),
              ]),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MetronomePresets.patterns.keys.map((key) {
                  final selected = key == _beatPattern;
                  return GestureDetector(
                    onTap: () => setState(() => _beatPattern = key),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? ZenColors.sage : ZenColors.surface,
                        border: Border.all(color: selected ? ZenColors.sage : ZenColors.hair),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(key, style: ZenText.button.copyWith(
                        color: selected ? Colors.white : ZenColors.ink,
                      )),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context, ClockEditorResult(
                    title: _titleCtl.text.isEmpty ? 'New clock' : _titleCtl.text,
                    description: _descCtl.text,
                    durationSeconds: _hours * 3600 + _minutes * 60 + _seconds,
                    color: _color,
                    bpm: _beatEnabled ? _bpm : null,
                    beatPattern: _beatEnabled ? _beatPattern : null,
                  ));
                },
                style: zenButton(foreground: ZenColors.sage, border: ZenColors.sage),
                child: Text(widget.existing == null ? 'Add' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WheelPicker extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  const _WheelPicker({required this.label, required this.value, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 120,
      child: ListWheelScrollView.useDelegate(
        itemExtent: 40,
        physics: const FixedExtentScrollPhysics(),
        controller: FixedExtentScrollController(initialItem: value),
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: max + 1,
          builder: (_, i) => Center(
            child: Text(
              i.toString().padLeft(2, '0'),
              style: ZenText.monoDigitSmall.copyWith(
                fontSize: i == value ? 24 : 16,
                color: i == value ? ZenColors.ink : ZenColors.secondary,
                fontWeight: i == value ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/widgets/clock_editor_sheet.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock/widgets/clock_editor_sheet.dart
git commit -m "feat(clock): extract ClockEditorSheet with Beat section"
```

---

## Task 10: ClocksTab (rebuilt from current grid + records)

**Files:**
- Create: `lib/lab/demos/clock/widgets/clocks_tab.dart`

**Interfaces:**
- Produces: `class ClocksTab extends StatelessWidget` rendering a Zen-styled grid of clock cards + records list below + shake-to-start header.

- [ ] **Step 1: Implement ClocksTab**

Create `lib/lab/demos/clock/widgets/clocks_tab.dart`. It uses `Provider<LabClockProvider>` from the parent and renders:

- A header row with the shake-to-start toggle.
- A 2-column `GridView` of `LabClockCard` widgets (rebuilt from the existing `_ClockCard`).
- A divider + "Records" header below the grid.
- A vertical list of `LabClockRecord` rows with swipe actions (use the existing `_RecordSwipeAction` from `clock_demo.dart` — refactor that widget into a separate file in this same task).
- A "+" FAB to open the editor.

The full implementation is long; port the existing `_ClockCard` (lines 1573-1724 in current `clock_demo.dart`) and `_buildModernRecordItem` (lines 660-792) plus `_RecordSwipeAction` (lines 1396-1570) into standalone widgets in the same file. Use `zenCard()` for containers and `zenButton()` for action buttons.

Specific structural rules:

- Clock card: title (16px ink), large mono digit showing `_formatTime(remainingSeconds)` (40px), small "×" close button top-right (44x44 hit area), beat dot + bpm text bottom-left (only if `clock.bpm != null`), play/pause + reset buttons (each 44x44 circular).
- Each card opens the `ClockEditorSheet` on tap and shows a confirm dialog on ×.
- Record row: leading icon (sage check if completed, secondary ⏰ if running), title + subtitle, trailing duration pill in mono. Long-press title → rename dialog. Swipe left → Create / Delete.
- Beat dot: a 12px circle. Sage when active (`isRunning && bpm != null && !silenced`). Hollow when not running. Dimmed when silenced.

Use the `LabClock` color field via `int.parse(clock.color.replaceFirst('#', '0xFF'))`.

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/widgets/clocks_tab.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock/widgets/clocks_tab.dart
git commit -m "feat(clock): add ClocksTab (grid + records + shake header) in Zen style"
```

---

## Task 11: TrackEditorPage

**Files:**
- Create: `lib/lab/demos/clock/widgets/track_editor_page.dart`

**Interfaces:**
- Produces: `Future<LabTrack?> showTrackEditor(BuildContext context, {LabTrack? existing})` — returns `null` if cancelled. Reads clocks from `LabClockProvider`.

- [ ] **Step 1: Implement TrackEditorPage**

Create `lib/lab/demos/clock/widgets/track_editor_page.dart`. Layout:

- App bar "Edit Track" or "New Track" with a save text-button.
- Title input + description input.
- "Source" section: horizontal scroll of clock chips. Each chip = `InkWell` showing title (16px), duration mono (12px), color dot. Tap a chip → append a `LabTrackSegment` to the track's segments list.
- "Sequence" section: a vertical list of placed segments, each row showing order index, title, duration, and × button (44x44). Order is fixed; v1 doesn't support drag-reorder.
- "Total" line at the bottom in mono.
- Save → `Navigator.pop(context, LabTrack(...))`.

Use `zenCard()` for each segment row, `zenButton()` for the save button.

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/widgets/track_editor_page.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock/widgets/track_editor_page.dart
git commit -m "feat(clock): add TrackEditorPage (palette + sequence)"
```

---

## Task 12: TrackRunnerPage

**Files:**
- Create: `lib/lab/demos/clock/widgets/track_runner_page.dart`

**Interfaces:**
- Produces: `class TrackRunnerPage extends StatelessWidget` — a full-screen page driven by `LabTrackProvider`.

- [ ] **Step 1: Implement TrackRunnerPage**

Create `lib/lab/demos/clock/widgets/track_runner_page.dart`. Layout:

- App bar: ← back + track title + ✕.
- Top: small "Segment X of N" label.
- Middle: current segment title (24px), big mono digit (64px) showing remaining time (negative allowed → display `-MM:SS`).
- Below: a stacked progress bar (segment-local on top, track-global on bottom), each 6px tall.
- Below: a 4-dot `BeatIndicator` row (sage dot, hollow when segment has no bpm, dim when beat was stolen). Static widget; no need to wire to `MetronomeFFI.tickStream`.
- Bottom action bar: Pause / Resume (44x44 icon button), Skip Segment (44x44), Stop (44x44 sage outline).
- If `LabTrackProvider.activeTrackId == null` (track was stopped externally), auto-pop after 1 second.

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/widgets/track_runner_page.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock/widgets/track_runner_page.dart
git commit -m "feat(clock): add TrackRunnerPage (full-screen segment runner)"
```

---

## Task 13: TracksTab

**Files:**
- Create: `lib/lab/demos/clock/widgets/tracks_tab.dart`

**Interfaces:**
- Produces: `class TracksTab extends StatelessWidget` — list of `LabTrackCard` widgets, FAB to open the editor, ▶ Run button per card.

- [ ] **Step 1: Implement TracksTab**

Create `lib/lab/demos/clock/widgets/tracks_tab.dart`. Layout:

- App bar: "Tracks" + history icon (opens `TrackRecordsPage`).
- A vertical list of `LabTrackCard` widgets:
  - Card: title (16px), "N segments · MM:SS total" subtitle in mono, 3 actions: Edit (text button), ▶ Run (sage filled 44px button), 🗑 Delete (icon).
  - Run is disabled (greyed) if `LabClockProvider.activeBeatClockId != null` (i.e. a clock is currently beating — track needs to wait).
  - Run is also disabled if `LabTrackProvider.activeTrackId != null` (another track is running).
- FAB: "+" → opens `TrackEditorPage`.

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/widgets/tracks_tab.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock/widgets/tracks_tab.dart
git commit -m "feat(clock): add TracksTab (list + edit + run)"
```

---

## Task 14: TrackRecordsPage

**Files:**
- Create: `lib/lab/demos/clock/widgets/track_records_page.dart`

**Interfaces:**
- Produces: `class TrackRecordsPage extends StatelessWidget` — list of `LabTrackRecord` with rename / delete actions.

- [ ] **Step 1: Implement TrackRecordsPage**

Create `lib/lab/demos/clock/widgets/track_records_page.dart`. Layout:

- App bar: ← back + "Track records" + "Clear" text button.
- Vertical list of record rows. Each row: leading icon (sage ✓ if completed, secondary ⏰ if running), title (16px), subtitle "MM-DD HH:mm · planned 10m · actual 8m 12s" in 13px secondary, trailing "Delete" icon button.
- Long-press title → rename dialog (TextField + Save / Cancel).
- Clear button → confirm dialog → `LabTrackProvider.deleteRecord` not yet implemented; for v1 just call `clearRecords()` (add a clearRecords method to `LabTrackProvider` mirroring `LabClockProvider.clearRecords`).

Add to `LabTrackProvider` (also in this task):

```dart
Future<void> clearRecords() async {
  _records.clear();
  await _saveRecords();
  notifyListeners();
}

Future<void> deleteRecord(String id) async {
  _records.removeWhere((r) => r.id == id);
  await _saveRecords();
  notifyListeners();
}

Future<void> updateRecordTitle(String id, String customTitle) async {
  final i = _records.indexWhere((r) => r.id == id);
  if (i == -1) return;
  _records[i] = _records[i].copyWith(customTitle: customTitle);
  await _saveRecords();
  notifyListeners();
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/widgets/track_records_page.dart lib/lab/demos/clock/providers/lab_track_provider.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock/widgets/track_records_page.dart \
        lib/lab/demos/clock/providers/lab_track_provider.dart
git commit -m "feat(clock): add TrackRecordsPage + record CRUD on provider"
```

---

## Task 15: DashboardTab

**Files:**
- Create: `lib/lab/demos/clock/widgets/dashboard_tab.dart`

**Interfaces:**
- Produces: `class DashboardTab extends StatelessWidget` — basic stats + recent records.

- [ ] **Step 1: Implement DashboardTab**

Create `lib/lab/demos/clock/widgets/dashboard_tab.dart`. Layout:

- App bar: "Dashboard".
- Three stat tiles in a row (or column if narrow):
  - "Today" — sum of `LabClockProvider.getRecordLiveDuration(r) + LabTrackProvider.getRecordLiveDuration(r)` for records whose `startTime` is today.
  - "Clocks done" — count of `LabClockProvider.records.where((r) => r.completed).length`.
  - "Tracks done" — count of `LabTrackProvider.records.where((r) => r.completed).length`.
- "Recent" section header.
- A merged list of the latest 5 records (sort by `startTime` desc, take top 5). Each row: leading icon (clock vs queue_music), title, subtitle "MM-DD HH:mm · actual 4m 12s".

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock/widgets/dashboard_tab.dart`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock/widgets/dashboard_tab.dart
git commit -m "feat(clock): add DashboardTab (today + recent)"
```

---

## Task 16: Replace clock_demo.dart with tab shell

**Files:**
- Modify: `lib/lab/demos/clock_demo.dart`

**Interfaces:**
- Produces: `ClockDemo extends DemoPage` (unchanged API) whose `buildPage` returns a `MultiProvider` wrapping `_ClockShell`.

- [ ] **Step 1: Replace clock_demo.dart body**

The new `clock_demo.dart` (entire file, ~120 lines) is:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../lab_container.dart';
import 'clock/providers/lab_clock_provider.dart';
import 'clock/providers/lab_track_provider.dart';
import 'clock/widgets/clocks_tab.dart';
import 'clock/widgets/tracks_tab.dart';
import 'clock/widgets/dashboard_tab.dart';
import 'clock/widgets/zen_theme.dart';

class ClockDemo extends DemoPage {
  @override
  String get title => 'Clock';
  @override
  String get slug => 'clock';
  @override
  String get description => '时钟 · 编排 · 节拍';
  @override
  bool get preferFullScreen => true;

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

class _ClockShell extends StatefulWidget {
  const _ClockShell();
  @override
  State<_ClockShell> createState() => _ClockShellState();
}

class _ClockShellState extends State<_ClockShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: ZenColors.bg,
        canvasColor: ZenColors.bg,
        primaryColor: ZenColors.sage,
        splashColor: ZenColors.sage.withValues(alpha: 0.1),
        highlightColor: ZenColors.sage.withValues(alpha: 0.05),
        fontFamily:
            '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
      ),
      home: Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [ClocksTab(), TracksTab(), DashboardTab()],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: ZenColors.surface,
          indicatorColor: ZenColors.sage.withValues(alpha: 0.15),
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.access_time_outlined), selectedIcon: Icon(Icons.access_time), label: 'Clocks'),
            NavigationDestination(icon: Icon(Icons.queue_music_outlined), selectedIcon: Icon(Icons.queue_music), label: 'Tracks'),
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run analyze**

Run: `flutter analyze lib/lab/demos/clock_demo.dart lib/lab/demos/clock/`
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/clock_demo.dart
git commit -m "refactor(clock): replace monolith with 3-tab shell (Clocks/Tracks/Dashboard)"
```

---

## Task 17: Update demo slug test to match new title

**Files:**
- Modify: `test/lab/demos/demo_slug_test.dart`

- [ ] **Step 1: Update the test for new title**

The existing test `demoRegistry.get('clock')` expects `title == '时钟'`. Change to `'Clock'`:

```dart
test('demoRegistry.get(slug) 命中（clock）', () {
  final demo = demoRegistry.get('clock');
  expect(demo, isNotNull);
  expect(demo!.title, 'Clock');
});
```

And the `getBySlug / getByTitle` test:

```dart
test('getBySlug / getByTitle 分离', () {
  expect(demoRegistry.getBySlug('clock')?.title, 'Clock');
  expect(demoRegistry.getByTitle('Clock')?.slug, 'clock');
});
```

- [ ] **Step 2: Run all lab tests**

Run: `flutter test test/lab/`
Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add test/lab/demos/demo_slug_test.dart
git commit -m "test: update slug test to match new clock title"
```

---

## Task 18: Grep guard for special fonts

**Files:**
- Create: `test/lab/demos/clock/no_special_fonts_test.dart`

- [ ] **Step 1: Write a guard test**

Create a regression test that fails CI if anyone reintroduces `Georgia`, `Playfair`, or `font-style: italic` in the clock widget files.

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final dir = Directory(p.join('lib', 'lab', 'demos', 'clock', 'widgets'));
  if (!dir.existsSync()) {
    test('widgets dir exists', () => fail('lib/lab/demos/clock/widgets not found'));
    return;
  }

  test('no Georgia / Playfair / italic in clock widgets', () {
    final offenders = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      for (final banned in ['Georgia', 'Playfair', 'font-style: italic', 'fontStyle: FontStyle.italic']) {
        if (text.contains(banned)) offenders.add('${f.path}: $banned');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Banned tokens found:\n${offenders.join('\n')}');
  });
}
```

- [ ] **Step 2: Run the test**

Run: `flutter test test/lab/demos/clock/no_special_fonts_test.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/lab/demos/clock/no_special_fonts_test.dart
git commit -m "test(clock): guard against Georgia/Playfair/italic in clock widgets"
```

---

## Task 19: End-to-end verify (analyze + build + analyze again)

**Files:** None.

- [ ] **Step 1: flutter analyze (whole project)**

Run: `flutter analyze lib/`
Expected: 0 errors. If errors appear, fix them inline (do not skip).

- [ ] **Step 2: flutter test (whole project)**

Run: `flutter test`
Expected: all pass. Fix any failures.

- [ ] **Step 3: flutter build apk --debug**

Run: `flutter build apk --debug`
Expected: build succeeds. This validates CMake / Oboe FFI linking, which `analyze` cannot see.

- [ ] **Step 4: Manual smoke test**

(Per the spec's 10-step smoke test, performed on a real Android device.)

1. Open Clock demo → 3 tabs visible, no wave divider, Zen palette.
2. Add a clock 5:00 with beat 60bpm 4/4. Card shows beat dot + "60bpm".
3. ▶ → metronome starts; verify in another audio app that Oboe is live.
4. Wait past 5:00 → display shows negative. Beat continues.
5. Reset → record appears. Swipe left → "Create" → new clock created.
6. Tracks tab → + → tap 2 clocks in palette → save.
7. ▶ Run track → first segment counts down → auto-advance → second → end.
8. Dashboard tab → "Today: 5m 0s" + 1 record.
9. Long-press record → rename works.
10. Shake device → first stopped clock starts (if toggle is on).

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit --allow-empty -m "chore: clock+beat+track restructure verified end-to-end"
```

---

## Self-Review (after writing the plan)

1. **Spec coverage:**
   - Context / Goals / Non-Goals: covered by the plan's intro and Global Constraints.
   - Data model (LabClock +bpm/+beatPattern, LabTrack, LabTrackRecord, storage keys): Tasks 2, 3, 4, 6.
   - BeatCoordinator singleton: Task 5.
   - LabTrackProvider with snapshot semantics: Task 7.
   - LabClockProvider beat hook + drop vibration: Task 6.
   - 3 tabs (Clocks/Tracks/Dashboard): Tasks 10, 13, 15 + shell in 16.
   - TrackEditorPage, TrackRunnerPage, TrackRecordsPage: Tasks 11, 12, 14.
   - ClockEditorSheet with Beat section: Task 9.
   - Zen palette + no special fonts + 44px buttons: Task 8 + guard test in Task 18.
   - Feature inventory doc: Task 1.
   - Drop vibration / wave divider / old data: Tasks 6, 16.
   - End-to-end verification: Task 19.

2. **Placeholder scan:** No TBDs, no "fill in later". The 8-color palette in Task 9 has explicit hex values. The 4-dot BeatIndicator in Task 12 is described as static. The test in Task 18 is self-contained.

3. **Type consistency:** `BeatCoordinator.requestOwnership` signature is identical in Tasks 5, 6, 7. `LabTrack.copyWith` fields are referenced consistently in Task 7. `ClockEditorResult` field names match the consumer in Tasks 10/16. The `providerId: 'clock:$id'` and `'track:$trackId'` prefix convention is consistent in Tasks 6 and 7.

4. **Risk mitigations from the spec:** Oboe stream reuse (relied on `pause_metronome` not tearing down — verified in spec analysis), copyWith quirk (Task 2 step 3 calls out explicit field passing), drag-and-drop scope (Tasks 11/13 explicitly note v1 limitation), build verification (Task 19 step 3 mandates `flutter build apk --debug`).
