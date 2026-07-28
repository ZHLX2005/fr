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
