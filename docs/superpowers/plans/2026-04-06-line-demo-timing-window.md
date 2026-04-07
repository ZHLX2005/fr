# line_demo 判定窗口缩放实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将速度滑杆替换为判定窗口缩放滑杆，修复速度与判定时机的耦合问题

**Architecture:** 下落时间固定为谱面 `dropDuration`，用户调节的 `timingScale` 仅影响判定窗口大小。设置页面演示区增加判定区域可视化。

**Tech Stack:** Flutter, SharedPreferences, CustomPainter

---

## 文件变更概览

| 文件 | 变更 |
|------|------|
| `lib/core/line/settings/line_settings.dart` | 替换速度滑杆为判定缩放滑杆；增强 `_DemoPainter` 绘制判定区域 |
| `lib/core/line/pages/line_demo_page.dart` | 移除速度控制；从 chart 读取固定下落时间；应用 scale 到判定窗口 |

---

## Task 1: 更新 `line_settings.dart` — 持久化 key

**Files:**
- Modify: `lib/core/line/settings/line_settings.dart:9-11`

- [ ] **Step 1: 替换 key 定义**

```dart
// 删除
const String lineSpeedKey = 'line_demo_speed';

// 新增
const String lineTimingScaleKey = 'line_demo_timing_scale';
const String lineBackgroundKey = 'line_demo_background';
```

- [ ] **Commit**

```bash
git add lib/core/line/settings/line_settings.dart
git commit -m "refactor(line): rename lineSpeedKey to lineTimingScaleKey"
```

---

## Task 2: 更新 `line_settings.dart` — 状态和加载逻辑

**Files:**
- Modify: `lib/core/line/settings/line_settings.dart`

- [ ] **Step 1: 替换状态变量**

在 `_SpeedSettingsPageState` 中：

```dart
// 删除
double _dropDurationMs = 2500.0;
static const double _minDropMs = 800.0;
static const double _maxDropMs = 4000.0;

// 新增
double _timingScale = 1.0;
static const double _minTimingScale = 0.5;
static const double _maxTimingScale = 2.0;
```

- [ ] **Step 2: 更新 `_loadSettings` 方法**

```dart
Future<void> _loadSettings() async {
  final prefs = await SharedPreferences.getInstance();
  if (mounted) {
    setState(() {
      _timingScale = prefs.getDouble(lineTimingScaleKey) ?? 1.0;
      final bgIndex = prefs.getInt(lineBackgroundKey) ?? 0;
      _backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
    });
  }
}
```

- [ ] **Step 3: 替换 `_saveSpeed` 为 `_saveTimingScale`**

```dart
Future<void> _saveTimingScale(double value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(lineTimingScaleKey, value);
}
```

- [ ] **Step 4: Commit**

```bash
git add lib/core/line/settings/line_settings.dart
git commit -m "refactor(line): replace speed state with timingScale state"
```

---

## Task 3: 更新 `line_settings.dart` — 演示区动画逻辑

**Files:**
- Modify: `lib/core/line/settings/line_settings.dart`

- [ ] **Step 1: 更新 `_fallController` 的 duration 逻辑**

删除 `_fallController.duration = Duration(milliseconds: _dropDurationMs.round());` 的所有调用。动画 duration 改为固定值（从外部传入或使用默认值 2500ms）。

```dart
// 在 initState 中，删除：
// _fallController.duration = Duration(milliseconds: _dropDurationMs.round());

// 在 _loadSettings 中删除对应行
// 在 _startFall 中删除对应行
```

注意：由于演示动画与游戏分离，演示动画的 duration 保持 2500ms 固定（代表谱面设计的典型下落时间），不随用户调节改变。

- [ ] **Step 2: 更新 `_onFallTick` 和 `_triggerExplode`**

保持现有逻辑不变。

- [ ] **Step 3: Commit**

```bash
git add lib/core/line/settings/line_settings.dart
git commit -m "refactor(line): fix demo animation duration"
```

---

## Task 4: 更新 `line_settings.dart` — 滑杆 UI

**Files:**
- Modify: `lib/core/line/settings/line_settings.dart`

- [ ] **Step 1: 替换 `_buildSpeedControls` 为 `_buildTimingControls`**

```dart
Widget _buildTimingControls(ThemeData theme, double Function(double) rpx) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(
        '判定缩放',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '${_timingScale.toStringAsFixed(1)}x',
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
          value: _timingScale,
          min: _minTimingScale,
          max: _maxTimingScale,
          onChanged: (v) {
            setState(() => _timingScale = v);
            _saveTimingScale(v);
          },
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '精准',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            '宽容',
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

- [ ] **Step 2: 更新 `build` 方法中的控制区引用**

```dart
// 原:
_child: _currentTab == 0
    ? _buildSpeedControls(theme, rpx)
    : _buildBackgroundControls(theme, rpx),

// 改为:
child: _currentTab == 0
    ? _buildTimingControls(theme, rpx)
    : _buildBackgroundControls(theme, rpx),
```

- [ ] **Step 3: 更新 Tab 标签**

```dart
// _buildTabs 中的两个 tab
_buildTabItem('判定', 0, theme),  // 原 '速度'
_buildTabItem('背景样式', 1, theme),
```

- [ ] **Step 4: Commit**

```bash
git add lib/core/line/settings/line_settings.dart
git commit -m "refactor(line): replace speed slider with timing scale slider"
```

---

## Task 5: 增强 `_DemoPainter` — 绘制判定区域

**Files:**
- Modify: `lib/core/line/settings/line_settings.dart`

- [ ] **Step 1: 更新 `_DemoPainter` 添加判定区域参数**

```dart
class _DemoPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double judgeYRatio;
  final double circleYRatio;
  final bool showExplode;
  final double explodeProgress;
  final List<Particle> explodeParticles;
  final BackgroundStyle backgroundStyle;
  final double timingScale;  // 新增

  _DemoPainter({
    required this.color,
    required this.radius,
    required this.judgeYRatio,
    required this.circleYRatio,
    this.showExplode = false,
    this.explodeProgress = 0.0,
    this.explodeParticles = const [],
    this.backgroundStyle = BackgroundStyle.none,
    this.timingScale = 1.0,  // 新增
  });
```

- [ ] **Step 2: 在 `paint` 方法中添加判定区域绘制**

在判定线绘制之后（`canvas.drawLine` 之后），添加：

```dart
// 判定区域可视化（设置页面演示用）
final perfectWindow = 50.0 * timingScale;
final greatWindow = 100.0 * timingScale;
final goodWindow = 150.0 * timingScale;
final missWindow = 200.0 * timingScale;

// 假设音符经过判定线的速度为 screenHeight / 2500ms * timingScale
// 转换为像素区域：ms × (像素/ms)
final pixelsPerMs = size.height * 0.75 / 2500; // 基于 judgeY 在 0.75 高度
final perfectHeight = perfectWindow * pixelsPerMs;
final greatHeight = greatWindow * pixelsPerMs;
final goodHeight = goodWindow * pixelsPerMs;
final missHeight = missWindow * pixelsPerMs;

final judgeY = size.height * judgeYRatio;

// Perfect 区域（最内层，绿色）
final perfectPaint = Paint()
  ..color = const Color(0xFF4CAF50).withValues(alpha: 0.15);
canvas.drawRect(
  Rect.fromLTWH(0, judgeY - perfectHeight, size.width, perfectHeight),
  perfectPaint,
);

// Great 区域（黄色）
final greatPaint = Paint()
  ..color = const Color(0xFFFFEB3B).withValues(alpha: 0.12);
canvas.drawRect(
  Rect.fromLTWH(0, judgeY - perfectHeight - greatHeight, size.width, greatHeight),
  greatPaint,
);

// Good 区域（橙色）
final goodPaint = Paint()
  ..color = const Color(0xFFFF9800).withValues(alpha: 0.10);
canvas.drawRect(
  Rect.fromLTWH(0, judgeY - perfectHeight - greatHeight - goodHeight, size.width, goodHeight),
  goodPaint,
);

// Miss 区域（最外层，红色）
final missPaint = Paint()
  ..color = const Color(0xFFF44336).withValues(alpha: 0.08);
canvas.drawRect(
  Rect.fromLTWH(0, judgeY - perfectHeight - greatHeight - goodHeight - missHeight, size.width, missHeight),
  missPaint,
);
```

- [ ] **Step 3: 更新 `shouldRepaint`**

```dart
@override
bool shouldRepaint(_DemoPainter oldDelegate) =>
    oldDelegate.circleYRatio != circleYRatio ||
    oldDelegate.showExplode != showExplode ||
    oldDelegate.explodeProgress != explodeProgress ||
    oldDelegate.backgroundStyle != backgroundStyle ||
    oldDelegate.timingScale != timingScale;  // 新增
```

- [ ] **Step 4: 更新 `build` 中 `_DemoPainter` 的构造**

```dart
CustomPaint(
  painter: _DemoPainter(
    color: widget.primaryColor,
    radius: rpx(20),
    judgeYRatio: 0.75,
    circleYRatio: _circleYRatio,
    showExplode: _showExplode,
    explodeProgress: _explodeController.value,
    explodeParticles: _explodeParticles,
    backgroundStyle: _backgroundStyle,
    timingScale: _timingScale,  // 新增
  ),
),
```

- [ ] **Step 5: Commit**

```bash
git add lib/core/line/settings/line_settings.dart
git commit -m "feat(line): add judgment zone visualization to demo painter"
```

---

## Task 6: 更新 `line_demo_page.dart` — 移除速度控制

**Files:**
- Modify: `lib/core/line/pages/line_demo_page.dart`

- [ ] **Step 1: 删除速度相关状态和 key**

```dart
// 删除
// double _dropDurationMs = 2500.0;  // 这行删除
// static const String _speedKey = lineSpeedKey;  // 删除这行
```

- [ ] **Step 2: 更新 `_loadSettings`**

```dart
Future<void> _loadSettings() async {
  final prefs = await SharedPreferences.getInstance();
  try {
    final chartJson = await rootBundle.loadString('assets/charts/test_chart.json');
    final chartData = ChartData.fromJson(jsonDecode(chartJson));
    if (mounted) {
      setState(() {
        _chart = chartData;
        _highScore = prefs.getInt(_highScoreKey) ?? 0;
        // 不再加载 _dropDurationMs，固定使用 chartData.dropDuration
        final bgIndex = prefs.getInt(_backgroundKey) ?? 0;
        _backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _highScore = prefs.getInt(_highScoreKey) ?? 0;
        // 不再设置 _dropDurationMs
      });
    }
  }
}
```

- [ ] **Step 3: 更新 `_spawnPendingNotes` 中的 dropMs 来源**

```dart
void _spawnPendingNotes() {
  if (_chart == null || _isGameOver) return;
  final elapsed = _gameStopwatch.elapsedMilliseconds;
  final dropMs = _chart!.dropDuration;  // 改为从 chart 读取

  while (_nextNoteIndex < _chart!.notes.length) {
    ...
  }
}
```

- [ ] **Step 4: 更新 `_spawnNote` 中的 duration**

```dart
void _spawnNote(NoteEvent event) {
  ...
  final controller = AnimationController(
    duration: Duration(milliseconds: _chart!.dropDuration),  // 改为从 chart 读取
    vsync: this,
  );
  ...
}
```

- [ ] **Step 5: 添加 timingScale 状态和持久化**

```dart
// 添加
double _timingScale = 1.0;
static const String _timingScaleKey = lineTimingScaleKey;
static const String _backgroundKey = lineBackgroundKey;
static const String _highScoreKey = 'line_demo_high_score';

// 在 _loadSettings 中加载
_timingScale = prefs.getDouble(_timingScaleKey) ?? 1.0;

// 添加保存方法
Future<void> _saveTimingScale(double value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_timingScaleKey, value);
}
```

- [ ] **Step 6: 判定窗口应用 scale**

在 `_handleColumnTap`、`_handleColumnPress`、`_handleSwipe` 中，判定窗口判断使用：

```dart
// 原:
if (diff <= _goodWindow) { ... }

// 改为:
final scaledGoodWindow = (_goodWindow * _timingScale).round();
if (diff <= scaledGoodWindow) { ... }
```

对 `_perfectWindow`、`_greatWindow`、`_goodWindow`、`_missWindow` 都应用同样的缩放。

- [ ] **Step 7: 在 `_showSpeedSettings` 调用后重新加载 timingScale**

`_showSpeedSettings` 的 `.then` 中已经调用 `_loadSettings`，所以会重新加载 `_timingScale`。

- [ ] **Step 8: Commit**

```bash
git add lib/core/line/pages/line_demo_page.dart
git commit -m "refactor(line): remove speed control, use chart dropDuration + timingScale"
```

---

## Task 7: 验证并测试

**Files:**
- Test: 运行游戏，验证判定区域可视化正常工作

- [ ] **Step 1: 运行应用**

```bash
flutter run
```

- [ ] **Step 2: 进入设置页面，确认**
- Tab "判定" 显示
- 滑杆显示 "1.0x"，拖动范围 0.5x ~ 2.0x
- 演示区显示判定区域带，颜色分层

- [ ] **Step 3: 进入游戏，确认**
- 音符按谱面 `dropDuration` 固定速度下落
- 判定窗口已缩放

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "fix(line): ensure timing scale changes are reflected in game"
```

---

## 自检清单

- [ ] spec 中每个需求都有对应 task
- [ ] 无 placeholder (TBD/TODO)
- [ ] 类型一致性检查：`_chart!.dropDuration` 用法在整个文件中一致
- [ ] 判定窗口缩放在所有判定处一致应用
