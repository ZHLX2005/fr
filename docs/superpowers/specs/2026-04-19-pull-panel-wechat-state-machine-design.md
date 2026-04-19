# Pull Panel (WeChat-like Light-Pull Reachable) Design

> **Context:** Refactor `lib/lab/demos/pull_panel_demo.dart` so interaction is stable and deterministic.
> We want to replicate WeChat-style "light pull is reachable" behavior: slow/light but continuous pull can still reach the full panel.
>
> **Key decision:** The state machine is the Single Source Of Truth (SSOT) for `state` and `progress`.

## Goal

Make the pull panel demo behave like WeChat:

1. **Drag is always reachable**: while the finger keeps dragging downward, progress can keep increasing (with resistance) until open.
2. **Release semantics** (two thresholds + refresh hold):
   - `progress < refreshThreshold` -> snap back to collapsed (0.0)
   - `refreshThreshold <= progress < openThreshold` -> enter refresh mode and **snap to refreshHoldProgress**
   - `progress >= openThreshold` -> snap to expanded (1.0)
3. **Expanded close gesture**: when expanded, scrolling to top and continuing to overscroll upward can drag the panel closed; release snaps to close/open.
4. **Remove multi-source decisions**: no UI-layer `debugSetStateForTest/debugSetProgressForTest` to drive runtime behavior; no duplicated physics mapping.

## Non-goals

- Perfect pixel-identical WeChat UI.
- Supporting iOS/Android physics differences beyond stable behavior.
- Refactoring other demos or global lint cleanup.

## Current Problems (Root Causes)

1. **Not SSOT**: UI assigns `_progress` and also force-syncs state machine via `debugSet*` on every build/gesture, which prevents the SM from owning state evolution.
2. **Duplicated physics**: pixel->progress mapping exists in UI and SM (risk of divergence).
3. **Expanded detection by progress epsilon**: using `_progress >= 0.98` is fragile; animation tail can oscillate around the threshold and flip scrollability/gesture layers.
4. **Noisy scroll signals**: mixing multiple scroll notifications/sign conventions causes device-dependent behavior.

## Proposed Architecture (Recommended Approach)

**Approach:** SSOT state machine + UI as a thin adapter.

- State machine owns:
  - `PullPanelState state`
  - `double progress` (logical progress in [0..1])
  - drag accumulators (main drag px, close drag px)
  - thresholds + hint text
- UI owns:
  - AnimationController for snapping
  - Refresh async work
  - Rendering, including mapping `sm.progress` -> panel height

### State Definitions

We will use explicit states that map to interaction phases:

- `collapsed`
- `draggingMain`
- `refreshHolding` (refresh in progress, progress held at `refreshHoldProgress`)
- `settling` (snapping animation in progress; target stored)
- `expanded`
- `draggingCloseFromScroll`

### Key Parameters (Locked)

All normalized by `progress` (0..1):

- `refreshThreshold = 0.30`
- `openThreshold = 0.75`
- `refreshHoldProgress = 0.25`

Close behavior:

- `closeSnapThreshold = 0.85` (recommended; easier to close than 0.90)

Velocity override (optional but supported):

- `velocityOpen = 900` (downward fling opens)

### Single Physics Mapping

There must be **exactly one** pixel->progress mapping, in the state machine.

We keep `progress` clamped [0..1] for logic, but apply resistance for overshoot feel.

Implementation options:

1) Keep current piecewise resistance (fastest)
2) Replace with smooth exponential resistance (better continuity)

For this refactor, we will keep current mapping initially to minimize changes, but locate it in one place only.

## Events (UI -> SM)

The UI translates raw input into these events:

### Main drag

- `onMainDragStart()`
- `onMainDragUpdate({deltaDyPx, fullHeightPx})` -> updates `progress` continuously (reachable)
- `onMainDragEnd({velocityDyPxPerSec})` -> returns an action

### Expanded close from scroll

- `onPanelTopOverscroll({overscrollDyPx, fullHeightPx})`
  - Only used when `state == expanded || state == draggingCloseFromScroll`
  - Accumulates close drag and updates `progress` down from 1.0
- `onPanelScrollEnd()` -> returns an action

### Async lifecycle

- `onRefreshCompleted()` -> returns action `animateTo(0.0)`

### Animation lifecycle

- `onExternalProgressTick(progress)` (optional; only if SM needs to observe animation frames)
- `onSettleCompleted(targetProgress)` -> sets terminal state:
  - target 1.0 -> `expanded`
  - target 0.0 -> `collapsed`
  - target refreshHoldProgress -> `refreshHolding`

## Actions (SM -> UI)

- `none`
- `animateTo(targetProgress)`
- `startRefresh`

**Rule:** The UI must only change progress through:
- calling SM update events, and
- executing SM returned actions and feeding completion back via `onSettleCompleted`.

## Release Semantics (Main Drag)

On `onMainDragEnd`:

- If `progress >= openThreshold` OR `velocityDy > velocityOpen`:
  - state -> `settling`
  - action -> `animateTo(1.0)`

- Else if `progress >= refreshThreshold`:
  - state -> `settling`
  - actions (in order):
    1) `startRefresh`
    2) `animateTo(refreshHoldProgress)`

- Else:
  - state -> `settling`
  - action -> `animateTo(0.0)`

## Expanded Close Semantics

While expanded, top overscroll upward should reduce progress.

- Overscroll updates push `progress` from 1.0 downwards.
- On scroll end:
  - if `progress < closeSnapThreshold` -> `animateTo(0.0)`
  - else -> `animateTo(1.0)`

## UI Integration Rules

1. **No always-on full-screen GestureDetector** when expanded/refreshing.
2. `scrollable` is derived from **SM state** (not progress epsilon):
   - allow panel grid scroll when `state == expanded || state == draggingCloseFromScroll`
3. Hint text is `sm.hintText` only.
4. Remove runtime use of `debugSet*` methods.

## Testing Strategy

Unit tests (`flutter test`) cover the SSOT rules:

- Main drag end in each region snaps to correct target and triggers refresh.
- Fast downward fling opens.
- Expanded close overscroll + end snaps close/open based on closeSnapThreshold.
- Hint text matches state/thresholds.

Integration tests are out-of-scope for this demo.

## Success Criteria

- Continuous slow drag can still reach open state.
- Release behavior is consistent with hint text.
- Expanded close is stable (no dependency on ScrollUpdate sign).
- No UI <-> SM double-ownership (SSOT achieved).
