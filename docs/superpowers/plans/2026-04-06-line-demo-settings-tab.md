# Line Demo 设置页 Tab 化 + 持久化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将速度设置页扩展为 Tab 式设置页（速度 | 背景样式），新增网格/线条/无三种背景选择，所有设置持久化到 SharedPreferences，并在游戏画面绘制对应背景。

**Architecture:** 在现有 `SpeedSettingsPage` 上增加 tab 切换逻辑和背景选择 UI。`GamePainter` 增加背景绘制。`_LineDemoPageState` 从 SharedPreferences 读取持久化设置。数据模型新增 `BackgroundStyle` 枚举。

**Tech Stack:** Flutter CustomPaint, SharedPreferences, AnimationController

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/lab/demos/line_demo_models.dart` | Modify | 新增 `BackgroundStyle` 枚举 |
| `lib/lab/demos/line_demo_painters.dart` | Modify | `GamePainter` 增加 `backgroundStyle` 参数，绘制网格/竖线背景 |
| `lib/lab/demos/line_demo_settings.dart` | Modify | Tab 化 UI，背景选择，持久化读写速度和背景 |
| `lib/lab/demos/line_demo.dart` | Modify | 读取持久化设置，传 `backgroundStyle` 给 `GamePainter` |

---

### Task 1: 新增 BackgroundStyle 枚举

**Files:**
- Modify: `lib/lab/demos/line_demo_models.dart`

- [ ] **Step 1: 在 `line_demo_models.dart` 末尾添加枚举**

在文件末尾（`JudgeFeedback` class 之后）添加：

```dart
/// 背景样式
enum BackgroundStyle {
  none,
  grid,
  lines;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/line_demo_models.dart
git commit -m "feat(line-demo): add BackgroundStyle enum"
```

---

### Task 2: GamePainter 绘制背景

**Files:**
- Modify: `lib/lab/demos/line_demo_painters.dart:10-155`

- [ ] **Step 1: 给 GamePainter 增加 backgroundStyle 参数**

在 `GamePainter` 构造函数中新增参数，在 `paint()` 方法中判定线绘制之前添加背景绘制逻辑。

在 `GamePainter` 的字段声明区（line 11-19 之后）添加：

```dart
  final BackgroundStyle backgroundStyle;
```

在构造函数（line 21-31）中添加参数：

```dart
    required this.backgroundStyle,
```

- [ ] **Step 2: 在 paint() 方法中判定线绘制之前添加背景绘制**

在 `paint()` 方法中，`// ── 判定线 ──` 注释之前插入：

```dart
    // ── 背景 ──
    if (backgroundStyle == BackgroundStyle.grid) {
      final gridPaint = Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      final spacing = 25.0 * screenWidth / 750;
      for (double x = spacing; x < w; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, screenHeight), gridPaint);
      }
      for (double y = spacing; y < screenHeight; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
      }
    } else if (backgroundStyle == BackgroundStyle.lines) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      for (int i = 0; i < columnCount; i++) {
        final cx = colWidth * i + colWidth / 2;
        canvas.drawLine(Offset(cx, 0), Offset(cx, screenHeight), linePaint);
      }
    }
```

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/line_demo_painters.dart
git commit -m "feat(line-demo): draw grid/lines background in GamePainter"
```

---

### Task 3: 游戏页读取持久化设置并传递给 GamePainter

**Files:**
- Modify: `lib/lab/demos/line_demo.dart`

- [ ] **Step 1: 新增 backgroundStyle 状态和持久化 key**

在 `_LineDemoPageState` 中（line 60 附近），在 `double _dropDurationMs = 2500.0;` 之后添加：

```dart
  BackgroundStyle _backgroundStyle = BackgroundStyle.none;

  static const String _speedKey = 'line_demo_speed';
  static const String _backgroundKey = 'line_demo_background';
```

删除旧的 `static const String _highScoreKey = 'line_demo_high_score';`（line 77），改为上面三个 key。

- [ ] **Step 2: 修改 _loadHighScore 为 _loadSettings，同时读取速度和背景**

将 `_loadHighScore` 方法（line 106-111）改为：

```dart
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _highScore = prefs.getInt('line_demo_high_score') ?? 0;
        _dropDurationMs = prefs.getDouble(_speedKey) ?? 2500.0;
        final bgIndex = prefs.getInt(_backgroundKey) ?? 0;
        _backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
      });
    }
  }
```

- [ ] **Step 3: 修改 initState 调用**

将 `initState` 中的 `_loadHighScore()`（line 95）改为 `_loadSettings()`。

- [ ] **Step 4: 修改 _saveHighScore 同时保存速度**

将 `_saveHighScore` 方法（line 113-119）改为：

```dart
  Future<void> _saveHighScore() async {
    if (_score > _highScore) {
      _highScore = _score;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('line_demo_high_score', _highScore);
    }
  }
```

（保持不变，只需确认 key 还是 `'line_demo_high_score'`。）

- [ ] **Step 5: 修改 _showSpeedSettings 返回后不依赖 pop value**

将 `_showSpeedSettings` 方法（line 408-441）改为：

```dart
  void _showSpeedSettings() {
    _wasGameRunning = !_isGameOver && !_isCountingDown;

    _pausedSnapshots = [];
    for (final col in _columns) {
      final snapshots = <double>[];
      for (final c in col) {
        snapshots.add(c.controller.value);
        c.controller.stop();
      }
      _pausedSnapshots.add(snapshots);
    }
    _stopSpawnTimers();
    for (final e in _explodes) {
      e.controller.stop();
    }

    Navigator.of(context)
        .push<void>(
      MaterialPageRoute(
        builder: (context) => SpeedSettingsPage(
          primaryColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    )
        .then((_) {
      if (!mounted || _isExiting) return;
      // 从 SharedPreferences 重新读取设置
      _loadSettings().then((_) {
        _startCountdown();
      });
    });
  }
```

- [ ] **Step 6: 在 GamePainter 调用处传入 backgroundStyle**

在 `build()` 方法中 `GamePainter` 的构造（line 557-566）添加参数：

```dart
                    painter: GamePainter(
                      columns: _columns,
                      explodes: _explodes,
                      color: theme.colorScheme.primary,
                      radius: radius,
                      screenWidth: w,
                      screenHeight: h,
                      columnCount: _columnCount,
                      judgeY: judgeY,
                      judgeFeedbacks: _judgeFeedbacks,
                      backgroundStyle: _backgroundStyle,
                    ),
```

- [ ] **Step 7: Commit**

```bash
git add lib/lab/demos/line_demo.dart
git commit -m "feat(line-demo): load persisted speed & background settings, pass to GamePainter"
```

---

### Task 4: 重构 SpeedSettingsPage 为 Tab 式

**Files:**
- Modify: `lib/lab/demos/line_demo_settings.dart`

这是最大的改动。将整个文件重构为 Tab 式设置页。

- [ ] **Step 1: 完整重写 line_demo_settings.dart**

用以下内容替换整个文件：

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'line_demo_models.dart';
import 'line_demo_painters.dart';

// ═══════════════════════════════════════════════════════════════
// 持久化 key
// ═══════════════════════════════════════════════════════════════

const String _speedKey = 'line_demo_speed';
const String _backgroundKey = 'line_demo_background';

// ═══════════════════════════════════════════════════════════════
// 演示动画绘制器：只绘制中间列单个圆圈 + 判定线 + 炸开粒子
// ═══════════════════════════════════════════════════════════════

class _DemoPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double judgeYRatio;
  final double circleYRatio;
  final bool showExplode;
  final double explodeProgress;
  final List<Particle> explodeParticles;
  final BackgroundStyle backgroundStyle;

  _DemoPainter({
    required this.color,
    required this.radius,
    required this.judgeYRatio,
    required this.circleYRatio,
    this.showExplode = false,
    this.explodeProgress = 0.0,
    this.explodeParticles = const [],
    this.backgroundStyle = BackgroundStyle.none,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final actualJudgeY = h * judgeYRatio;
    final actualCircleY = h * circleYRatio;

    // ── 背景 ──
    if (backgroundStyle == BackgroundStyle.grid) {
      final gridPaint = Paint()
        ..color = color.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      final spacing = radius * 1.2;
      for (double x = spacing; x < w; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
      }
      for (double y = spacing; y < h; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
      }
    } else if (backgroundStyle == BackgroundStyle.lines) {
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawLine(Offset(cx, 0), Offset(cx, h), linePaint);
    }

    // 判定线
    final judgePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, actualJudgeY), Offset(w, actualJudgeY), judgePaint);

    // 圆圈
    if (!showExplode) {
      final circlePaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, actualCircleY), radius, circlePaint);
    }

    // 炸开动画
    if (showExplode) {
      _paintExplode(canvas, cx, actualJudgeY * 0.7, w);
    }
  }

  void _paintExplode(Canvas canvas, double cx, double explodeY, double w) {
    if (explodeProgress <= 0.08) {
      final t = explodeProgress / 0.08;
      final easedT = Curves.easeIn.transform(t);
      final currentRadius = radius * (1.0 - easedT);
      if (currentRadius > 0.1) {
        final paint = Paint()
          ..color = color.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(Offset(cx, explodeY), currentRadius, paint);
      }
    }

    if (explodeProgress > 0.08) {
      final t = (explodeProgress - 0.08) / 0.92;
      final splashProgress = Curves.easeOut.transform(t);
      final fadeProgress = Curves.easeIn.transform(t);
      final particleSize = 8.0 * w / 200;

      for (final p in explodeParticles) {
        final startX = cx + radius * math.cos(p.angle);
        final startY = explodeY + radius * math.sin(p.angle);
        final dx = math.cos(p.angle) * p.distance * splashProgress;
        final dy = math.sin(p.angle) * p.distance * splashProgress;
        final currentAlpha = p.initialAlpha * (1.0 - fadeProgress);

        if (currentAlpha > 0.01) {
          final particlePaint = Paint()
            ..color = color.withValues(alpha: currentAlpha)
            ..style = PaintingStyle.fill;
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(startX + dx, startY + dy),
              width: particleSize,
              height: particleSize,
            ),
            particlePaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DemoPainter oldDelegate) =>
      oldDelegate.circleYRatio != circleYRatio ||
      oldDelegate.showExplode != showExplode ||
      oldDelegate.explodeProgress != explodeProgress ||
      oldDelegate.backgroundStyle != backgroundStyle;
}

// ═══════════════════════════════════════════════════════════════
// 设置页面（Tab 式：速度 | 背景样式）
// ═══════════════════════════════════════════════════════════════

class SpeedSettingsPage extends StatefulWidget {
  final Color primaryColor;

  const SpeedSettingsPage({
    required this.primaryColor,
  });

  @override
  State<SpeedSettingsPage> createState() => _SpeedSettingsPageState();
}

class _SpeedSettingsPageState extends State<SpeedSettingsPage>
    with TickerProviderStateMixin {
  // Tab 状态
  int _currentTab = 0; // 0: 速度, 1: 背景样式

  // 速度
  late double _dropDurationMs;
  static const double _minDropMs = 800.0;
  static const double _maxDropMs = 4000.0;

  // 背景
  BackgroundStyle _backgroundStyle = BackgroundStyle.none;

  // 落体动画
  double _circleYRatio = -0.05;
  bool _showExplode = false;
  List<Particle> _explodeParticles = [];

  late AnimationController _fallController;
  late AnimationController _explodeController;

  static const double _targetYRatio = 0.525; // judgeYRatio * 0.7 = 0.75 * 0.7

  @override
  void initState() {
    super.initState();
    _loadSettings();

    _fallController = AnimationController(
      duration: Duration(milliseconds: _dropDurationMs.round()),
      vsync: this,
    );

    _explodeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fallController.addListener(_onFallTick);
    _explodeController.addListener(_onExplodeTick);

    _startFall();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dropDurationMs = prefs.getDouble(_speedKey) ?? 2500.0;
        final bgIndex = prefs.getInt(_backgroundKey) ?? 0;
        _backgroundStyle = BackgroundStyle.values[bgIndex.clamp(0, BackgroundStyle.values.length - 1)];
        _fallController.duration = Duration(milliseconds: _dropDurationMs.round());
      });
    }
  }

  Future<void> _saveSpeed(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speedKey, value);
  }

  Future<void> _saveBackground(BackgroundStyle style) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_backgroundKey, style.index);
  }

  void _startFall() {
    _showExplode = false;
    _explodeParticles = [];
    _circleYRatio = -0.05;
    _fallController.duration = Duration(milliseconds: _dropDurationMs.round());
    _fallController.forward(from: 0.0);
  }

  void _onFallTick() {
    if (_showExplode) return;
    final easedT = Curves.easeIn.transform(_fallController.value);
    setState(() {
      _circleYRatio = -0.05 + (_targetYRatio + 0.05) * easedT;
    });

    if (_fallController.value >= 1.0) {
      _triggerExplode();
    }
  }

  void _triggerExplode() {
    setState(() {
      _showExplode = true;
      _explodeParticles = _generateDemoParticles();
    });
    _explodeController.forward(from: 0.0);
  }

  void _onExplodeTick() {
    setState(() {});
    if (_explodeController.value >= 1.0) {
      _startFall();
    }
  }

  List<Particle> _generateDemoParticles() {
    final rng = math.Random();
    final count = 4 + rng.nextInt(2);
    final particles = <Particle>[];
    final baseAngles = List.generate(count, (i) => (2 * math.pi * i / count));
    final distances = List.generate(count, (i) => 15.0 + i * 5.0);
    final alphas = List.generate(count, (i) => 0.5 - i * 0.1);

    for (int i = 0; i < count; i++) {
      final angle = baseAngles[i] + (rng.nextDouble() - 0.5) * 0.6;
      particles.add(Particle(
        angle: angle,
        distance: distances[i] + rng.nextDouble() * 5,
        initialAlpha: alphas[i],
      ));
    }
    return particles;
  }

  @override
  void dispose() {
    _fallController.dispose();
    _explodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = MediaQuery.of(context).size.width;
    double rpx(double v) => v * w / 750;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // 返回按钮
            Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 20,
                  color: widget.primaryColor,
                ),
              ),
            ),

            // 主内容
            Padding(
              padding: EdgeInsets.only(
                top: 56,
                left: 32,
                right: 32,
                bottom: MediaQuery.of(context).padding.bottom + 32,
              ),
              child: Column(
                children: [
                  // ── Tab 按钮 ──
                  _buildTabs(theme, rpx),

                  const SizedBox(height: 16),

                  // ── 预览动画区 (60%) ──
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 0.6,
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_fallController, _explodeController]),
                          builder: (context, _) {
                            return Container(
                              decoration: BoxDecoration(
                                color: widget.primaryColor.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(rpx(16)),
                                border: Border.all(
                                  color: widget.primaryColor.withValues(alpha: 0.2),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(rpx(16)),
                                child: CustomPaint(
                                  painter: _DemoPainter(
                                    color: widget.primaryColor,
                                    radius: rpx(20),
                                    judgeYRatio: 0.75,
                                    circleYRatio: _circleYRatio,
                                    showExplode: _showExplode,
                                    explodeProgress: _explodeController.value,
                                    explodeParticles: _explodeParticles,
                                    backgroundStyle: _backgroundStyle,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── 控制区 (40%) ──
                  Expanded(
                    flex: 4,
                    child: _currentTab == 0
                        ? _buildSpeedControls(theme, rpx)
                        : _buildBackgroundControls(theme, rpx),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(ThemeData theme, double Function(double) rpx) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildTabItem('速度', 0, theme),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '|',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w200,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ),
        ),
        _buildTabItem('背景样式', 1, theme),
      ],
    );
  }

  Widget _buildTabItem(String label, int index, ThemeData theme) {
    final isSelected = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w400 : FontWeight.w200,
              color: isSelected
                  ? widget.primaryColor
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 1,
            width: 40,
            color: isSelected
                ? widget.primaryColor
                : Colors.transparent,
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedControls(ThemeData theme, double Function(double) rpx) {
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
          '${_dropDurationMs.round()}ms',
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
            value: _dropDurationMs,
            min: _minDropMs,
            max: _maxDropMs,
            onChanged: (v) {
              setState(() => _dropDurationMs = v);
              _saveSpeed(v);
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '快',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '慢',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBackgroundControls(ThemeData theme, double Function(double) rpx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildBgButton(
              icon: _buildGridIcon(rpx),
              style: BackgroundStyle.grid,
              theme: theme,
            ),
            const SizedBox(width: 16),
            _buildBgButton(
              icon: _buildLinesIcon(rpx),
              style: BackgroundStyle.lines,
              theme: theme,
            ),
            const SizedBox(width: 16),
            _buildBgButton(
              icon: _buildNoneIcon(rpx),
              style: BackgroundStyle.none,
              theme: theme,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBgButton({
    required Widget icon,
    required BackgroundStyle style,
    required ThemeData theme,
  }) {
    final isSelected = _backgroundStyle == style;
    return GestureDetector(
      onTap: () {
        setState(() => _backgroundStyle = style);
        _saveBackground(style);
      },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? widget.primaryColor
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
          color: isSelected
              ? widget.primaryColor.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Center(child: icon),
      ),
    );
  }

  Widget _buildGridIcon(double Function(double) rpx) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: _GridIconPainter(
        color: widget.primaryColor.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildLinesIcon(double Function(double) rpx) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: _LinesIconPainter(
        color: widget.primaryColor.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildNoneIcon(double Function(double) rpx) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: _NoneIconPainter(
        color: widget.primaryColor.withValues(alpha: 0.6),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 背景图标绘制器
// ═══════════════════════════════════════════════════════════════

class _GridIconPainter extends CustomPainter {
  final Color color;
  _GridIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    // 3x3 grid
    for (int i = 1; i <= 2; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (int i = 1; i <= 2; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridIconPainter old) => old.color != color;
}

class _LinesIconPainter extends CustomPainter {
  final Color color;
  _LinesIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    // 3 vertical lines evenly spaced
    for (int i = 1; i <= 3; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinesIconPainter old) => old.color != color;
}

class _NoneIconPainter extends CustomPainter {
  final Color color;
  _NoneIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final margin = size.width * 0.2;
    canvas.drawLine(
      Offset(margin, margin),
      Offset(size.width - margin, size.height - margin),
      paint,
    );
    canvas.drawLine(
      Offset(size.width - margin, margin),
      Offset(margin, size.height - margin),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _NoneIconPainter old) => old.color != color;
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/lab/demos/line_demo_settings.dart
git commit -m "feat(line-demo): tab-based settings page with speed & background style"
```

---

### Task 5: 验证和修复

- [ ] **Step 1: 运行 Flutter 静态分析**

Run: `flutter analyze lib/lab/demos/`
Expected: No errors

- [ ] **Step 2: 修复任何分析错误**

如果 `flutter analyze` 报错，逐个修复后重新运行直到通过。

- [ ] **Step 3: Commit any fixes**

```bash
git add -u
git commit -m "fix(line-demo): resolve static analysis issues"
```
