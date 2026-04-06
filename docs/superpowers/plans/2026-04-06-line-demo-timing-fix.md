# Line Demo 判定时机修正 + 流速控制 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix spawn timing to match easeIn curve arrival at judgeLineRatio, and add scrollSpeed as independent control alongside timingScale.

**Architecture:** `timingScale` controls judge window size and health scaling only. `scrollSpeed` controls note fall duration and spawn timing. Both are persisted independently. The easeIn-to-judgeRatio constant (√0.75 ≈ 0.866) is computed once as a named constant.

**Tech Stack:** Flutter, SharedPreferences, AnimationController

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/core/line/settings/line_settings.dart` | Modify | Add scrollSpeed persistence key, scrollSpeed tab UI in settings page |
| `lib/core/line/pages/line_demo_page.dart` | Modify | Fix spawn timing, fix animation duration, add scrollSpeed state |

---

## Constants

In `line_demo_page.dart` (line 73 area), add after `_judgeLineRatio`:

```dart
// easeIn 曲线下，到达 judgeLineRatio 位置的动画进度：sqrt(0.75) ≈ 0.866
const double _easeInToJudgeRatio = 0.866;
```

In `line_settings.dart` (line 10 area), add new key:

```dart
const String lineScrollSpeedKey = 'line_demo_scroll_speed';
```

---

### Task 1: Add scrollSpeed state and persistence to line_demo_page.dart

**Files:**
- Modify: `lib/core/line/pages/line_demo_page.dart:69-71`

- [ ] **Step 1: Add _scrollSpeed state and key after _timingScale**

At line 69-70, after `double _timingScale = 1.0;` and its key, add:

```dart
double _scrollSpeed = 1.0;
static const String _scrollSpeedKey = lineScrollSpeedKey;
```

- [ ] **Step 2: Update _loadSettings to load scrollSpeed**

In `_loadSettings` (line 120-142), after loading `_timingScale`, add:

```dart
_scrollSpeed = prefs.getDouble(_scrollSpeedKey) ?? 1.0;
```

The setState block should look like:

```dart
setState(() {
  _chart = chartData;
  _timingScale = prefs.getDouble(_timingScaleKey) ?? 1.0;
  _scrollSpeed = prefs.getDouble(_scrollSpeedKey) ?? 1.0;
  _highScore = prefs.getInt(_highScoreKey) ?? 0;
  final bgIndex = prefs.getInt(_backgroundKey) ?? 0;
  _backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
});
```

- [ ] **Step 3: Commit**

```bash
git add lib/core/line/pages/line_demo_page.dart
git commit -m "feat(line-demo): add scrollSpeed state and persistence key"
```

---

### Task 2: Fix _spawnPendingNotes spawn timing

**Files:**
- Modify: `lib/core/line/pages/line_demo_page.dart:190-212`

- [ ] **Step 1: Fix spawn condition to use easeIn-corrected timing**

In `_spawnPendingNotes` (line 197), change:

```dart
if (elapsed >= event.time - dropMs) {
```

To:

```dart
final actualDropMs = dropMs / _scrollSpeed;
final spawnTime = event.time - (actualDropMs * _easeInToJudgeRatio).round();
if (elapsed >= spawnTime) {
```

- [ ] **Step 2: Fix the next event delay calculation**

In `_spawnPendingNotes` (line 207), change:

```dart
final delayMs = (nextEvent.time - dropMs - elapsed).clamp(1, 100);
```

To:

```dart
final nextActualDropMs = dropMs / _scrollSpeed;
final nextSpawnTime = nextEvent.time - (nextActualDropMs * _easeInToJudgeRatio).round();
final delayMs = (nextSpawnTime - elapsed).clamp(1, 100);
```

- [ ] **Step 3: Commit**

```bash
git add lib/core/line/pages/line_demo_page.dart
git commit -m "fix(line-demo): correct spawn timing with easeIn curve factor"
```

---

### Task 3: Fix _spawnNote animation duration

**Files:**
- Modify: `lib/core/line/pages/line_demo_page.dart:214-267`

- [ ] **Step 1: Fix animation duration to use scrollSpeed**

In `_spawnNote` (line 218-220), change:

```dart
final controller = AnimationController(
  duration: Duration(milliseconds: _chart!.dropDuration),
  vsync: this,
);
```

To:

```dart
final actualDropMs = (_chart!.dropDuration / _scrollSpeed).round();
final controller = AnimationController(
  duration: Duration(milliseconds: actualDropMs),
  vsync: this,
);
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/line/pages/line_demo_page.dart
git commit -m "fix(line-demo): use scrollSpeed-adjusted drop duration for note animation"
```

---

### Task 4: Verify auto-miss logic (no changes needed, confirm)**

**Files:**
- Review: `lib/core/line/pages/line_demo_page.dart:237-244`

The auto-miss check at line 239 is:
```dart
final missThreshold = event.time + (_missWindow * _timingScale).round();
```

This is **correct** — the miss threshold is relative to `event.time` (the hit moment), not to spawn or animation progress. No changes needed.

---

### Task 5: Add scrollSpeed persistence key to line_settings.dart

**Files:**
- Modify: `lib/core/line/settings/line_settings.dart:10-11`

- [ ] **Step 1: Add lineScrollSpeedKey after lineTimingScaleKey**

At line 10-11, after:

```dart
const String lineTimingScaleKey = 'line_demo_timing_scale';
const String lineBackgroundKey = 'line_demo_background';
```

Add:

```dart
const String lineScrollSpeedKey = 'line_demo_scroll_speed';
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/line/settings/line_settings.dart
git commit -m "feat(line-demo): add scrollSpeed persistence key"
```

---

### Task 6: Add scrollSpeed tab to SpeedSettingsPage

**Files:**
- Modify: `lib/core/line/settings/line_settings.dart`

- [ ] **Step 1: Update tab structure to 3 tabs: 判定 | 流速 | 背景样式**

In `_buildTabs` (line 429-448), change to:

```dart
Widget _buildTabs(ThemeData theme, double Function(double) rpx) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _buildTabItem('判定', 0, theme),
      _buildTabSeparator(theme),
      _buildTabItem('流速', 1, theme),
      _buildTabSeparator(theme),
      _buildTabItem('背景样式', 2, theme),
    ],
  );
}

Widget _buildTabSeparator(ThemeData theme) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      '|',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w200,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
      ),
    ),
  );
}
```

- [ ] **Step 2: Add _scrollSpeed state and load/save methods**

In `_SpeedSettingsPageState` (line 206 area), add after `_timingScale` state:

```dart
double _scrollSpeed = 1.0;
static const double _minScrollSpeed = 0.5;
static const double _maxScrollSpeed = 2.0;
```

Add save method after `_saveTimingScale`:

```dart
Future<void> _saveScrollSpeed(double value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(lineScrollSpeedKey, value);
}
```

- [ ] **Step 3: Update _loadSettings to load scrollSpeed**

In `_loadSettings` (line 250 area), add:

```dart
_scrollSpeed = prefs.getDouble(lineScrollSpeedKey) ?? 1.0;
```

- [ ] **Step 4: Update control area to show 3 tabs**

In `build()` method (line 416 area), change:

```dart
Expanded(
  flex: 4,
  child: _currentTab == 0
      ? _buildTimingControls(theme, rpx)
      : _buildBackgroundControls(theme, rpx),
),
```

To:

```dart
Expanded(
  flex: 4,
  child: _currentTab == 0
      ? _buildTimingControls(theme, rpx)
      : _currentTab == 1
          ? _buildScrollSpeedControls(theme, rpx)
          : _buildBackgroundControls(theme, rpx),
),
```

- [ ] **Step 5: Add _buildScrollSpeedControls method**

After `_buildTimingControls` (around line 530 area), add:

```dart
Widget _buildScrollSpeedControls(ThemeData theme, double Function(double) rpx) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        '下落速度',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '${_scrollSpeed.toStringAsFixed(1)}x',
        style: TextStyle(
          fontSize: rpx(32),
          fontWeight: FontWeight.w100,
          color: widget.primaryColor.withValues(alpha: 0.4),
          fontFeatures: [const FontFeature.tabularFigures()],
        ),
      ),
      const SizedBox(height: 16),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 1.5,
          thumbShape: const LineThumbShape(thumbRadius: 4),
          overlayShape: SliderComponentShape.noOverlay,
          activeTrackColor: widget.primaryColor,
          inactiveTrackColor: theme.colorScheme.outlineVariant,
          thumbColor: widget.primaryColor,
        ),
        child: Slider(
          value: _scrollSpeed,
          min: _minScrollSpeed,
          max: _maxScrollSpeed,
          onChanged: (v) {
            setState(() => _scrollSpeed = v);
            _saveScrollSpeed(v);
            // Restart demo animation with new speed
            _fallController.duration = Duration(milliseconds: (2500 / v).round());
            if (!_showExplode) {
              _fallController.forward(from: _fallController.value);
            }
          },
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '慢',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '快',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ],
  );
}
```

- [ ] **Step 6: Commit**

```bash
git add lib/core/line/settings/line_settings.dart
git commit -m "feat(line-demo): add scrollSpeed tab to settings page"
```

---

### Task 7: Verify and analyze

- [ ] **Step 1: Run Flutter static analysis**

```bash
flutter analyze lib/core/line/
```

Expected: No errors

- [ ] **Step 2: Fix any analysis errors**

- [ ] **Step 3: Commit any fixes**

```bash
git add -u && git commit -m "fix(line-demo): resolve static analysis issues"
```

---

## Self-Review Checklist

- [ ] `actualDropMs = dropMs / _scrollSpeed` used in both `_spawnPendingNotes` and `_spawnNote`? ✓
- [ ] `_easeInToJudgeRatio = 0.866` constant defined and used in spawn timing? ✓
- [ ] `missThreshold = event.time + (_missWindow * _timingScale).round()` unchanged (correct)? ✓
- [ ] Settings page tab order: 判定 | 流速 | 背景样式? ✓
- [ ] Demo animation duration = 2500ms / scrollSpeed? ✓
- [ ] All three SharedPreferences keys: `lineTimingScaleKey`, `lineScrollSpeedKey`, `lineBackgroundKey`? ✓
