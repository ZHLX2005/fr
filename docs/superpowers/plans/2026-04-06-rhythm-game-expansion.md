# Rhythm Game Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand line demo from tap-only to full rhythm game with three note types (tap/hold/slide), JSON chart loading, and health bar system.

**Architecture:** Replace random spawning with chart-driven master clock. FallingNote replaces FallingCircle. Time-based hit detection replaces position-based. Health bar replaces 3-miss rule.

**Tech Stack:** Flutter CustomPaint, AnimationController, GestureDetector, Stopwatch, JSON parsing, SharedPreferences

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/lab/demos/line_demo_models.dart` | Modify | Add NoteType, SlideDirection, NoteEvent, FallingNote; keep Particle, JudgeFeedback, BackgroundStyle, ExplodeAnimation; remove FallingCircle |
| `lib/lab/demos/line_demo_painters.dart` | Major rewrite | GamePainter draws FallingNote (tap/hold/slide) + health bar + background |
| `lib/lab/demos/line_demo.dart` | Major rewrite | Master clock, chart loading, three hit detections, health bar, gestures |
| `lib/lab/demos/line_demo_settings.dart` | No change | Speed and background settings unchanged |
| `assets/charts/test_chart.json` | Already created | Test chart (151s, ~200 notes) |
| `pubspec.yaml` | Modify | Register `assets/charts/` |

---

### Task 1: Data models

**Files:**
- Modify: `lib/lab/demos/line_demo_models.dart`

- [ ] **Step 1: Add new enums and classes, remove FallingCircle**

Replace the entire file with:

```dart
import 'package:flutter/material.dart';

/// 音符类型
enum NoteType { tap, hold, slide }

/// 滑动方向
enum SlideDirection { up, down, left, right }

/// 背景样式
enum BackgroundStyle {
  none,
  grid,
  lines;
}

/// 谱面音符事件
class NoteEvent {
  final int time; // ms，音符到达判定线的时间
  final int column; // 0/1/2
  final NoteType type;
  final SlideDirection? direction; // 仅 slide
  final int? holdDuration; // 仅 hold，ms

  const NoteEvent({
    required this.time,
    required this.column,
    required this.type,
    this.direction,
    this.holdDuration,
  });

  factory NoteEvent.fromJson(Map<String, dynamic> json) {
    return NoteEvent(
      time: json['time'] as int,
      column: json['column'] as int,
      type: NoteType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NoteType.tap,
      ),
      direction: json['direction'] != null
          ? SlideDirection.values.firstWhere(
              (e) => e.name == json['direction'],
              orElse: () => SlideDirection.up,
            )
          : null,
      holdDuration: json['holdDuration'] as int?,
    );
  }
}

/// 谱面数据
class ChartData {
  final String name;
  final int bpm;
  final int dropDuration;
  final List<NoteEvent> notes;

  const ChartData({
    required this.name,
    required this.bpm,
    required this.dropDuration,
    required this.notes,
  });

  factory ChartData.fromJson(Map<String, dynamic> json) {
    final rawNotes = json['notes'] as List;
    final notes = rawNotes
        .whereType<Map<String, dynamic>>()
        .map((n) => NoteEvent.fromJson(n))
        .toList();
    return ChartData(
      name: json['name'] as String? ?? 'Unnamed',
      bpm: json['bpm'] as int? ?? 120,
      dropDuration: json['dropDuration'] as int? ?? 2500,
      notes: notes,
    );
  }
}

/// 下落中的音符（运行时）
class FallingNote {
  final NoteEvent event;
  final AnimationController controller;
  double currentY;
  bool judged;
  bool holding; // 仅 hold：正在被按住
  double holdProgress; // 仅 hold：按住进度 0~1

  FallingNote({
    required this.event,
    required this.controller,
    required this.currentY,
  })  : judged = false,
        holding = false,
        holdProgress = 0.0;
}

/// 炸开动画状态
class ExplodeAnimation {
  final AnimationController controller;
  final double x;
  final double y;
  final List<Particle> particles;
  final double radius;

  ExplodeAnimation({
    required this.controller,
    required this.x,
    required this.y,
    required this.particles,
    required this.radius,
  });
}

/// 粒子数据
class Particle {
  final double angle;
  final double distance;
  final double initialAlpha;

  const Particle({
    required this.angle,
    required this.distance,
    required this.initialAlpha,
  });
}

/// 判定文字反馈
class JudgeFeedback {
  final String text;
  final double x;
  final double y;
  final Color color;
  final double baseAlpha;
  final AnimationController controller;

  JudgeFeedback({
    required this.text,
    required this.x,
    required this.y,
    required this.color,
    required this.baseAlpha,
    required this.controller,
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/line_demo_models.dart
git commit -m "refactor(line-demo): replace FallingCircle with NoteType/NoteEvent/FallingNote models"
```

---

### Task 2: Register chart assets in pubspec.yaml

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add assets section**

In `pubspec.yaml`, after `uses-material-design: true` (line 163), add:

```yaml
  assets:
    - assets/charts/
```

- [ ] **Step 2: Commit**

```bash
git add pubspec.yaml
git commit -m "chore(line-demo): register chart assets in pubspec.yaml"
```

---

### Task 3: Rewrite GamePainter for three note types + health bar

**Files:**
- Modify: `lib/lab/demos/line_demo_painters.dart`

- [ ] **Step 1: Replace GamePainter**

Replace the existing `GamePainter` class (lines 10-181) with a new version that:
- Accepts `List<List<FallingNote>>` instead of `List<List<FallingCircle>>`
- Adds `double health` parameter (0.0-1.0)
- Draws tap notes as circles (same as before)
- Draws hold notes as long bars with head/tail circles + connecting rectangle + progress fill
- Draws slide notes as circles with directional arrows inside
- Draws health bar on the right side

The new `GamePainter` constructor:

```dart
class GamePainter extends CustomPainter {
  final List<List<FallingNote>> columns;
  final List<ExplodeAnimation> explodes;
  final Color color;
  final double radius;
  final double screenWidth;
  final double screenHeight;
  final int columnCount;
  final double judgeY;
  final List<JudgeFeedback> judgeFeedbacks;
  final BackgroundStyle backgroundStyle;
  final double health; // 0.0 - 1.0

  GamePainter({
    required this.columns,
    required this.explodes,
    required this.color,
    required this.radius,
    required this.screenWidth,
    required this.screenHeight,
    required this.columnCount,
    required this.judgeY,
    required this.judgeFeedbacks,
    required this.backgroundStyle,
    required this.health,
  });
```

The `paint()` method structure:

```dart
@override
void paint(Canvas canvas, Size size) {
  final w = size.width;
  final h = size.height;
  final colWidth = w / columnCount;

  // 1. Background (grid/lines/none) — same as current
  // 2. Health bar — right side
  _paintHealthBar(canvas, w, h);
  // 3. Judge line — same as current
  // 4. Notes — iterate columns and FallingNote list
  for (int i = 0; i < columns.length; i++) {
    final cx = colWidth * i + colWidth / 2;
    for (final note in columns[i]) {
      if (note.judged && note.event.type != NoteType.hold) continue;
      if (note.event.type == NoteType.tap) {
        _paintTapNote(canvas, cx, note);
      } else if (note.event.type == NoteType.hold) {
        _paintHoldNote(canvas, cx, note, colWidth);
      } else if (note.event.type == NoteType.slide) {
        _paintSlideNote(canvas, cx, note);
      }
    }
  }
  // 5. Explode animations — same as current
  // 6. Judge text feedback — same as current
}
```

**Health bar drawing (`_paintHealthBar`):**

```dart
void _paintHealthBar(Canvas canvas, double w, double h) {
  final barWidth = 8.0;
  final barX = w - 12 - barWidth;
  final barTop = 60.0;
  final barBottom = judgeY;
  final barHeight = barBottom - barTop;
  final barRadius = 4.0;

  // Background
  final bgPaint = Paint()
    ..color = color.withValues(alpha: 0.1)
    ..style = PaintingStyle.fill;
  final bgRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(barX, barTop, barWidth, barHeight),
    Radius.circular(barRadius),
  );
  canvas.drawRRect(bgRect, bgPaint);

  // Fill (from bottom up)
  final fillHeight = barHeight * health.clamp(0.0, 1.0);
  if (fillHeight > 0) {
    Color fillColor;
    if (health > 0.5) {
      fillColor = const Color(0xFF66BB6A); // green
    } else if (health > 0.3) {
      fillColor = const Color(0xFFFFA726); // orange
    } else {
      fillColor = const Color(0xFFEF5350); // red
    }
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(barX, barBottom - fillHeight, barWidth, fillHeight),
      Radius.circular(barRadius),
    );
    canvas.drawRRect(fillRect, fillPaint);
  }
}
```

**Tap note drawing (`_paintTapNote`):** Same as current circle drawing, but check `note.judged` to skip, and use `note.currentY` instead of `circle.currentY`. For missed notes, check if `note.currentY > judgeY` and `!note.judged` → auto-miss fade.

**Hold note drawing (`_paintHoldNote`):**

```dart
void _paintHoldNote(Canvas canvas, double cx, FallingNote note, double colWidth) {
  if (note.currentY < -radius * 2) return; // off screen top

  final headY = note.currentY;
  // Tail Y = head position - (holdDuration / dropDuration) * totalTravelDistance
  // But simpler: the hold bar extends upward from the head
  final holdLength = screenHeight * (note.event.holdDuration! / (dropDuration * 1.0));
  final tailY = headY - holdLength;

  final barWidth = radius * 0.6;
  final alpha = 0.3;

  // Connecting bar
  final barPaint = Paint()
    ..color = color.withValues(alpha: alpha * 0.5)
    ..style = PaintingStyle.fill;
  canvas.drawRect(
    Rect.fromLTWH(cx - barWidth / 2, tailY, barWidth, headY - tailY),
    barPaint,
  );

  // Progress fill (if being held)
  if (note.holding && note.holdProgress > 0) {
    final fillHeight = (headY - tailY) * note.holdProgress;
    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx - barWidth / 2, headY - fillHeight, barWidth, fillHeight),
      fillPaint,
    );
  }

  // Head circle
  final circlePaint = Paint()
    ..color = color.withValues(alpha: alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  canvas.drawCircle(Offset(cx, headY), radius * 0.6, circlePaint);

  // Tail circle
  if (tailY > -radius) {
    canvas.drawCircle(Offset(cx, tailY), radius * 0.6, circlePaint);
  }
}
```

Wait, the hold note needs `dropDuration` and `screenHeight` which are already fields on GamePainter. Also need to compute `holdLength` based on how far the note travels in `holdDuration` ms. The note falls `screenHeight` in `dropDuration` ms, so in `holdDuration` ms it travels `screenHeight * holdDuration / dropDuration`. But GamePainter doesn't have `dropDuration`. Add it as a parameter.

Add `final double dropDuration;` to GamePainter fields and constructor.

**Slide note drawing (`_paintSlideNote`):**

```dart
void _paintSlideNote(Canvas canvas, double cx, FallingNote note) {
  if (note.currentY < -radius || note.currentY > screenHeight + radius) return;
  if (note.judged) return;

  // Circle (same as tap)
  final circlePaint = Paint()
    ..color = color.withValues(alpha: 0.3)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  canvas.drawCircle(Offset(cx, note.currentY), radius, circlePaint);

  // Arrow inside
  final arrowPaint = Paint()
    ..color = color.withValues(alpha: 0.5)
    ..style = PaintingStyle.fill;
  final arrowSize = radius * 0.6;
  _drawArrow(canvas, cx, note.currentY, arrowSize, note.event.direction!, arrowPaint);
}

void _drawArrow(Canvas canvas, double cx, double cy, double size, SlideDirection dir, Paint paint) {
  final path = Path();
  switch (dir) {
    case SlideDirection.up:
      path.moveTo(cx, cy - size);
      path.lineTo(cx - size * 0.7, cy + size * 0.3);
      path.lineTo(cx + size * 0.7, cy + size * 0.3);
      break;
    case SlideDirection.down:
      path.moveTo(cx, cy + size);
      path.lineTo(cx - size * 0.7, cy - size * 0.3);
      path.lineTo(cx + size * 0.7, cy - size * 0.3);
      break;
    case SlideDirection.left:
      path.moveTo(cx - size, cy);
      path.lineTo(cx + size * 0.3, cy - size * 0.7);
      path.lineTo(cx + size * 0.3, cy + size * 0.7);
      break;
    case SlideDirection.right:
      path.moveTo(cx + size, cy);
      path.lineTo(cx - size * 0.3, cy - size * 0.7);
      path.lineTo(cx - size * 0.3, cy + size * 0.7);
      break;
  }
  path.close();
  canvas.drawPath(path, paint);
}
```

The missed note fade logic: For tap and slide notes, if `!note.judged && note.currentY > judgeY`, apply fade like the current missed circle logic. For hold notes, auto-miss is handled by game logic.

Keep `WaterExitPainter` and `LineThumbShape` unchanged.

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/line_demo_painters.dart
git commit -m "feat(line-demo): GamePainter draws tap/hold/slide notes and health bar"
```

---

### Task 4: Rewrite game page — master clock, chart spawning, hit detection, health, gestures

**Files:**
- Modify: `lib/lab/demos/line_demo.dart`

This is the core task. The entire game logic is rewritten. Key changes:

1. **Remove** `_columns` (List<List<FallingCircle>>), `_spawnTimers`, `_missCount`, `_scheduleSpawn`, `_spawnCircle`, `_handleTap`, `_hitCircle`, `_onMiss`
2. **Add** `_notes` (List<List<FallingNote>>), `_chart` (ChartData), `_gameStopwatch`, `_nextNoteIndex`, `_health`, `_heldColumns` (Set<int>), `_swipeStart`
3. **Replace** random spawning with chart-driven spawning
4. **Replace** position-based hit detection with time-based
5. **Replace** GestureDetector with pan+tap gesture handling
6. **Replace** 3-miss with health bar

- [ ] **Step 1: Rewrite line_demo.dart**

Replace the entire file. The new `_LineDemoPageState` has these state fields:

```dart
class _LineDemoPageState extends State<_LineDemoPage>
    with TickerProviderStateMixin {
  // ── 水动画 ──
  bool _isWaterEntering = true;
  bool _isExiting = false;
  bool _isCountingDown = false;
  int _countdownValue = 3;
  late AnimationController _exitController;
  late AnimationController _enterController;

  // ── 谱面 ──
  ChartData? _chart;
  int _nextNoteIndex = 0;
  final Stopwatch _gameStopwatch = Stopwatch();

  // ── 游戏状态 ──
  static const int _columnCount = 3;
  List<List<FallingNote>> _notes = [];
  final List<ExplodeAnimation> _explodes = [];
  final List<JudgeFeedback> _judgeFeedbacks = [];

  // 分数 & 血条
  int _score = 0;
  double _health = 1.0;
  int _highScore = 0;
  bool _isGameOver = false;

  // 下落速度
  double _dropDurationMs = 2500.0;

  BackgroundStyle _backgroundStyle = BackgroundStyle.none;
  static const String _speedKey = 'line_demo_speed';
  static const String _backgroundKey = 'line_demo_background';

  static const double _circleRadiusRpx = 20.0;
  static const double _judgeLineRatio = 0.75;
  static const double _judgeRangeRpx = 100.0;

  // 判定窗口（ms）
  static const int _perfectWindow = 50;
  static const int _greatWindow = 100;
  static const int _goodWindow = 150;
  static const int _missWindow = 200;

  // 手势追踪
  final Set<int> _heldColumns = {}; // 当前按住的列
  Offset? _panStart; // 滑动起点
  int? _panColumn; // 滑动发生的列

  double _rpx(double value) => value * MediaQuery.of(context).size.width / 750;

  // 暂停
  bool _wasGameRunning = false;
  static const String _highScoreKey = 'line_demo_high_score';
```

**initState:**
- Same water animation setup
- `_notes = List.generate(_columnCount, (_) => []);`
- `_loadSettings()` loads chart + settings

**_loadSettings (new):**
```dart
Future<void> _loadSettings() async {
  final prefs = await SharedPreferences.getInstance();
  // Load chart
  final chartJson = await rootBundle.loadString('assets/charts/test_chart.json');
  final chartData = ChartData.fromJson(jsonDecode(chartJson));
  // Load settings
  if (mounted) {
    setState(() {
      _chart = chartData;
      _dropDurationMs = prefs.getDouble(_speedKey) ?? chartData.dropDuration.toDouble();
      _highScore = prefs.getInt('line_demo_high_score') ?? 0;
      final bgIndex = prefs.getInt(_backgroundKey) ?? 0;
      _backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
    });
  }
}
```

Add imports: `import 'dart:convert';`, `import 'package:flutter/services.dart';`

**Game start (replaces _startSpawnTimers):**

```dart
void _startGame() {
  _nextNoteIndex = 0;
  _gameStopwatch.reset();
  _gameStopwatch.start();
  _spawnPendingNotes();
}

void _spawnPendingNotes() {
  if (_chart == null || _isGameOver) return;
  final elapsed = _gameStopwatch.elapsedMilliseconds;
  final dropMs = _dropDurationMs.round();

  while (_nextNoteIndex < _chart!.notes.length) {
    final event = _chart!.notes[_nextNoteIndex];
    // Spawn when elapsed >= event.time - dropDuration
    if (elapsed >= event.time - dropMs) {
      _spawnNote(event);
      _nextNoteIndex++;
    } else {
      break;
    }
  }

  // Schedule next check
  if (_nextNoteIndex < _chart!.notes.length && !_isGameOver) {
    final nextEvent = _chart!.notes[_nextNoteIndex];
    final delayMs = (nextEvent.time - dropMs - elapsed).clamp(1, 100);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted && !_isGameOver) _spawnPendingNotes();
    });
  }
}

void _spawnNote(NoteEvent event) {
  final screenSize = MediaQuery.of(context).size;
  final radius = _rpx(_circleRadiusRpx);

  final controller = AnimationController(
    duration: Duration(milliseconds: _dropDurationMs.round()),
    vsync: this,
  );

  final note = FallingNote(controller: controller, currentY: -radius);

  controller.addListener(() {
    final easedT = Curves.easeIn.transform(controller.value);
    final targetY = screenSize.height + radius;
    note.currentY = -radius + (targetY + radius) * easedT;

    // Auto-miss for tap/slide notes that pass judge line beyond miss window
    if (!note.judged && event.type != NoteType.hold) {
      final judgeY = screenSize.height * _judgeLineRatio;
      if (note.currentY > judgeY) {
        final elapsed = _gameStopwatch.elapsedMilliseconds;
        if (elapsed > event.time + _missWindow) {
          _onNoteMissed(event.column, note);
        }
      }
    }
  });

  setState(() {
    _notes[event.column].add(note);
  });

  controller.forward().then((_) {
    note.controller.dispose();
    if (!mounted) return;
    setState(() {
      _notes[event.column].remove(note);
    });
  });
}
```

**Hit detection — Tap:**

```dart
void _handleColumnTap(int colIndex) {
  if (_isExiting || _isGameOver || _isCountingDown) return;
  if (_chart == null) return;

  final elapsed = _gameStopwatch.elapsedMilliseconds;

  // Find closest unjudged tap/slide note in this column near judge line
  FallingNote? best;
  int bestDiff = _missWindow + 1;

  for (final note in _notes[colIndex]) {
    if (note.judged) continue;
    if (note.event.type == NoteType.hold) continue; // hold handled separately
    if (note.event.type == NoteType.slide) continue; // slide needs swipe, not tap

    final diff = (elapsed - note.event.time).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = note;
    }
  }

  if (best == null || bestDiff > _goodWindow) return;

  _judgeNote(colIndex, best!, bestDiff);
}
```

**Hit detection — Hold:**

```dart
void _handleColumnPress(int colIndex) {
  if (_isExiting || _isGameOver || _isCountingDown) return;
  if (_chart == null) return;

  final elapsed = _gameStopwatch.elapsedMilliseconds;

  // Find unjudged hold note near judge line
  for (final note in _notes[colIndex]) {
    if (note.judged || note.event.type != NoteType.hold) continue;
    final diff = (elapsed - note.event.time).abs();
    if (diff <= _goodWindow) {
      note.holding = true;
      _heldColumns.add(colIndex);
      return;
    }
  }
}

void _handleColumnRelease(int colIndex) {
  _heldColumns.remove(colIndex);
  final elapsed = _gameStopwatch.elapsedMilliseconds;

  for (final note in _notes[colIndex]) {
    if (!note.holding || note.judged) continue;
    if (note.event.type != NoteType.hold) continue;

    // Check if held long enough
    final heldTime = elapsed - note.event.time;
    if (heldTime >= note.event.holdDuration! * 0.8) {
      final headDiff = 0; // head was caught in time (holding was started)
      _judgeNote(colIndex, note, headDiff);
    } else {
      // Released too early = miss
      _onNoteMissed(colIndex, note);
    }
    note.holding = false;
    return;
  }
}

// Call in controller listener for hold notes — update holdProgress
void _updateHoldNotes() {
  if (_chart == null) return;
  final elapsed = _gameStopwatch.elapsedMilliseconds;

  for (final col in _notes) {
    for (final note in col) {
      if (note.event.type != NoteType.hold || !note.holding || note.judged) continue;
      final heldTime = elapsed - note.event.time;
      note.holdProgress = (heldTime / note.event.holdDuration!).clamp(0.0, 1.0);

      if (note.holdProgress >= 1.0) {
        _judgeNote(_notes.indexOf(col), note, 0);
        note.holding = false;
      }
    }
  }
}
```

**Hit detection — Slide:**

```dart
void _handleSwipe(int colIndex, SlideDirection direction) {
  if (_isExiting || _isGameOver || _isCountingDown) return;
  if (_chart == null) return;

  final elapsed = _gameStopwatch.elapsedMilliseconds;

  for (final note in _notes[colIndex]) {
    if (note.judged || note.event.type != NoteType.slide) continue;
    final diff = (elapsed - note.event.time).abs();
    if (diff <= _goodWindow && note.event.direction == direction) {
      _judgeNote(colIndex, note, diff);
      return;
    }
  }
}
```

**Judge & score:**

```dart
void _judgeNote(int colIndex, FallingNote note, int timeDiffMs) {
  note.judged = true;

  String judgeText;
  double judgeAlpha;
  int points;
  double healthChange;

  if (timeDiffMs <= _perfectWindow) {
    judgeText = 'Perfect'; judgeAlpha = 0.6; points = 3; healthChange = 0.05;
  } else if (timeDiffMs <= _greatWindow) {
    judgeText = 'Great'; judgeAlpha = 0.4; points = 2; healthChange = 0.02;
  } else {
    judgeText = 'Good'; judgeAlpha = 0.25; points = 1; healthChange = 0.0;
  }

  final screenSize = MediaQuery.of(context).size;
  final w = screenSize.width;
  final colWidth = w / _columnCount;
  final centerX = colWidth * colIndex + colWidth / 2;
  final radius = _rpx(_circleRadiusRpx);

  final feedbackController = AnimationController(
    duration: const Duration(milliseconds: 600), vsync: this,
  );
  final feedback = JudgeFeedback(
    text: judgeText, x: centerX, y: note.currentY - radius - 20,
    color: Theme.of(context).colorScheme.primary,
    baseAlpha: judgeAlpha, controller: feedbackController,
  );

  setState(() {
    _score += points;
    _health = (_health + healthChange).clamp(0.0, 1.0);
    _judgeFeedbacks.add(feedback);
  });

  feedbackController.forward().then((_) {
    feedbackController.dispose();
    if (!mounted) return;
    setState(() => _judgeFeedbacks.remove(feedback));
  });

  // Explode animation (same as before)
  _createExplode(colIndex, centerX, note.currentY, radius);

  // Remove note after explode (for tap/slide)
  if (note.event.type != NoteType.hold) {
    note.controller.stop();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _notes[colIndex].remove(note);
      });
      note.controller.dispose();
    });
  }
}

void _onNoteMissed(int colIndex, FallingNote note) {
  if (note.judged) return;
  note.judged = true;
  setState(() {
    _health = (_health - 0.15).clamp(0.0, 1.0);
  });
  if (_health <= 0.0) {
    _gameOver();
  }
}
```

**Gesture handler:**

```dart
// In build(), replace GestureDetector with:
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTapUp: (details) {
    final col = _getColumnFromX(details.localPosition.dx);
    if (col != null) _handleColumnTap(col);
  },
  onPanStart: (details) {
    final col = _getColumnFromX(details.localPosition.dx);
    if (col != null) {
      _panStart = details.globalPosition;
      _panColumn = col;
      _handleColumnPress(col);
    }
  },
  onPanEnd: (details) {
    if (_panColumn != null) {
      _handleColumnRelease(_panColumn!);
    }
    // Check for swipe
    if (_panStart != null && _panColumn != null) {
      final velocity = details.velocity.pixelsPerSecond;
      final dir = _getSwipeDirection(velocity);
      if (dir != null) {
        _handleSwipe(_panColumn!, dir);
      }
    }
    _panStart = null;
    _panColumn = null;
  },
  child: Stack(...)
)

int? _getColumnFromX(double x) {
  final w = MediaQuery.of(context).size.width;
  final colWidth = w / _columnCount;
  for (int i = 0; i < _columnCount; i++) {
    if (x >= colWidth * i && x < colWidth * (i + 1)) return i;
  }
  return null;
}

SlideDirection? _getSwipeDirection(Offset velocity) {
  final dx = velocity.dx.abs();
  final dy = velocity.dy.abs();
  final threshold = 100.0; // minimum velocity
  if (dx < threshold && dy < threshold) return null;
  if (dx > dy) {
    return velocity.dx > 0 ? SlideDirection.right : SlideDirection.left;
  } else {
    return velocity.dy > 0 ? SlideDirection.down : SlideDirection.up;
  }
}
```

**GamePainter call in build():**

```dart
GamePainter(
  notes: _notes,
  explodes: _explodes,
  color: theme.colorScheme.primary,
  radius: radius,
  screenWidth: w,
  screenHeight: h,
  columnCount: _columnCount,
  judgeY: judgeY,
  judgeFeedbacks: _judgeFeedbacks,
  backgroundStyle: _backgroundStyle,
  health: _health,
  dropDuration: _dropDurationMs,
)
```

**Remove from build():** The `miss: _missCount/3` display (replace with nothing — health bar handles it).

**_gameOver:** Same as before but remove `_missCount`.

**_restartGame:** Reset `_health = 1.0`, `_nextNoteIndex = 0`, clear `_notes`, `_gameStopwatch.reset()`.

**_resumeFromSnapshot:** Replace `_startSpawnTimers()` call with `_startGame()` for first-start. For resume from pause, restart stopwatch offset and call `_spawnPendingNotes()`.

**_showSpeedSettings:** Same pause mechanism but `_notes` instead of `_columns`.

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/line_demo.dart
git commit -m "feat(line-demo): rewrite game with chart-driven spawning, three note types, health bar"
```

---

### Task 5: Verify & fix

- [ ] **Step 1: Run Flutter analyze**

Run: `flutter analyze lib/lab/demos/`
Expected: No errors in line_demo files

- [ ] **Step 2: Fix any analysis errors**

If errors found, fix and re-run.

- [ ] **Step 3: Commit fixes**

```bash
git add -u
git commit -m "fix(line-demo): resolve analysis errors"
```
