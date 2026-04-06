# Line Demo 设置页面重设计 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将线游戏速度设置从底部弹出面板改为全新左右分栏页面，左侧控制速度，右侧循环演示下落+炸开动画。

**Architecture:** 新增 `_SpeedSettingsPage` StatefulWidget 作为独立页面，通过 `Navigator.push` 导航。演示动画使用独立的 `AnimationController` 和简化版 `_DemoPainter`（只绘制中间列）。游戏暂停/恢复复用现有快照机制。所有改动集中在 `line_demo.dart` 单文件内。

**Tech Stack:** Flutter/Dart，CustomPainter，AnimationController

---

## File Structure

所有改动在单一文件内：

- **Modify:** `lib/lab/demos/line_demo.dart`
  - 新增 `_SpeedSettingsPage` + `_SpeedSettingsPageState`（设置页面）
  - 新增 `_DemoPainter`（演示动画绘制器，简化版 _GamePainter）
  - 修改 `_showSpeedSettings()`（从 BottomSheet 改为 Navigator.push）
  - 删除旧 BottomSheet 相关代码

---

### Task 1: 新增演示动画绘制器 `_DemoPainter`

**Files:**
- Modify: `lib/lab/demos/line_demo.dart` (在 `_GamePainter` 类之后添加)

- [ ] **Step 1: 添加 `_DemoPainter` 类**

在 `_GamePainter` 类之后、`_WaterExitPainter` 类之前，添加新的绘制器。它只绘制中间列的一个圆圈，不依赖 `_FallingCircle` 数据类：

```dart
/// 演示动画绘制器：只绘制中间列单个圆圈 + 判定线 + 炸开粒子
class _DemoPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double judgeY;
  final double circleY;       // 当前圆圈 Y 坐标
  final bool showExplode;     // 是否显示炸开
  final double explodeProgress; // 炸开进度 0~1
  final List<_Particle> explodeParticles;

  _DemoPainter({
    required this.color,
    required this.radius,
    required this.judgeY,
    required this.circleY,
    this.showExplode = false,
    this.explodeProgress = 0.0,
    this.explodeParticles = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;

    // 判定线
    final judgePaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, judgeY), Offset(w, judgeY), judgePaint);

    // 圆圈
    if (!showExplode) {
      final circlePaint = Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(cx, circleY), radius, circlePaint);
    }

    // 炸开动画
    if (showExplode) {
      // Phase 1: 内爆缩小 (0.0 - 0.08)
      if (explodeProgress <= 0.08) {
        final t = explodeProgress / 0.08;
        final easedT = Curves.easeIn.transform(t);
        final currentRadius = radius * (1.0 - easedT);
        if (currentRadius > 0.1) {
          final paint = Paint()
            ..color = color.withValues(alpha: 0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5;
          canvas.drawCircle(Offset(cx, judgeY * 0.7), currentRadius, paint);
        }
      }

      // Phase 2: 粒子飞溅 (0.08 - 1.0)
      if (explodeProgress > 0.08) {
        final t = (explodeProgress - 0.08) / 0.92;
        final splashProgress = Curves.easeOut.transform(t);
        final fadeProgress = Curves.easeIn.transform(t);
        final particleSize = 8.0 * w / 200;

        for (final p in explodeParticles) {
          final startX = cx + radius * math.cos(p.angle);
          final startY = judgeY * 0.7 + radius * math.sin(p.angle);
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
  }

  @override
  bool shouldRepaint(_DemoPainter oldDelegate) => true;
}
```

- [ ] **Step 2: 运行 `flutter analyze` 验证无语法错误**

Run: `flutter analyze lib/lab/demos/line_demo.dart`
Expected: No issues found

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/line_demo.dart
git commit -m "feat(line-demo): add _DemoPainter for settings preview animation"
```

---

### Task 2: 新增设置页面 `_SpeedSettingsPage`

**Files:**
- Modify: `lib/lab/demos/line_demo.dart` (在 `_DemoPainter` 之后添加)

- [ ] **Step 1: 添加 `_SpeedSettingsPage` 类**

在 `_DemoPainter` 类之后、`_WaterExitPainter` 类之前添加：

```dart
/// 速度设置页面
class _SpeedSettingsPage extends StatefulWidget {
  final double dropDurationMs;
  final Color primaryColor;

  const _SpeedSettingsPage({
    required this.dropDurationMs,
    required this.primaryColor,
  });

  @override
  State<_SpeedSettingsPage> createState() => _SpeedSettingsPageState();
}

class _SpeedSettingsPageState extends State<_SpeedSettingsPage>
    with TickerProviderStateMixin {
  late double _dropDurationMs;
  late AnimationController _fallController;
  late AnimationController _explodeController;
  late List<_Particle> _explodeParticles;

  double _circleY = -20.0;
  bool _showExplode = false;

  @override
  void initState() {
    super.initState();
    _dropDurationMs = widget.dropDurationMs;
    _explodeParticles = _generateDemoParticles();
    _initFallController();
    _initExplodeController();
    _startFall();
  }

  void _initFallController() {
    _fallController = AnimationController(
      duration: Duration(milliseconds: _dropDurationMs.round()),
      vsync: this,
    );
    _fallController.addListener(() {
      if (_showExplode) return;
      final easedT = Curves.easeIn.transform(_fallController.value);
      final boxH = 260.0; // 演示框高度近似
      final judgeY = boxH * 0.75;
      _circleY = -20.0 + (judgeY * 0.7 + 20.0) * easedT;
      setState(() {});
    });
  }

  void _initExplodeController() {
    _explodeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _explodeController.addListener(() {
      setState(() {});
    });
  }

  void _startFall() {
    _showExplode = false;
    _circleY = -20.0;
    _fallController.duration = Duration(milliseconds: _dropDurationMs.round());
    _fallController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      _triggerExplode();
    });
  }

  void _triggerExplode() {
    setState(() {
      _showExplode = true;
      _explodeParticles = _generateDemoParticles();
    });
    _explodeController.forward(from: 0.0).then((_) {
      if (!mounted) return;
      _startFall();
    });
  }

  List<_Particle> _generateDemoParticles() {
    final rng = math.Random();
    final count = 4 + rng.nextInt(2);
    final particles = <_Particle>[];
    final distances = List.generate(count, (i) => 15.0 + i * 5.0);
    final alphas = List.generate(count, (i) => 0.5 - i * 0.1);
    final baseAngles = List.generate(count, (i) => 2 * math.pi * i / count);
    for (int i = 0; i < count; i++) {
      final angle = baseAngles[i] + (rng.nextDouble() - 0.5) * 0.6;
      particles.add(_Particle(
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
    final color = widget.primaryColor;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // 返回按钮
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  color: color,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).pop(_dropDurationMs),
              ),
            ),

            // 主内容：左右分栏
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  children: [
                    // 左侧：控制区
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '下落速度',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${_dropDurationMs.round()}ms',
                            style: TextStyle(
                              fontSize: 32 * w / 750,
                              fontWeight: FontWeight.w100,
                              color: color.withValues(alpha: 0.4),
                              fontFeatures: [const FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 24),
                          SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 1.5,
                              thumbShape: const _LineThumbShape(thumbRadius: 4),
                              overlayShape: SliderComponentShape.noOverlay,
                              activeTrackColor: color,
                              inactiveTrackColor: theme.colorScheme.outlineVariant,
                              thumbColor: color,
                            ),
                            child: Slider(
                              value: _dropDurationMs,
                              min: _LineDemoPageState._minDropMs,
                              max: _LineDemoPageState._maxDropMs,
                              onChanged: (v) {
                                setState(() {
                                  _dropDurationMs = v;
                                  _fallController.duration =
                                      Duration(milliseconds: v.round());
                                });
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
                      ),
                    ),

                    const SizedBox(width: 24),

                    // 右侧：演示区
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 0.6,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16 * w / 750),
                              border: Border.all(
                                color: color.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16 * w / 750),
                              child: CustomPaint(
                                painter: _DemoPainter(
                                  color: color,
                                  radius: 15.0 * w / 750,
                                  judgeY: 0.75, // ratio
                                  circleY: _circleY,
                                  showExplode: _showExplode,
                                  explodeProgress: _explodeController.value,
                                  explodeParticles: _explodeParticles,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**注意**：`_minDropMs` 和 `_maxDropMs` 当前是 `_LineDemoPageState` 的 `static const`，所以可以直接访问。但需要将它们的可见性改为类外部可访问——实际上 `static const` 在同一文件内已经可以访问，无需修改。

- [ ] **Step 2: 运行 `flutter analyze` 验证**

Run: `flutter analyze lib/lab/demos/line_demo.dart`
Expected: No issues found（可能有 `_DemoPainter` 的 judgeY 类型问题，需修复）

- [ ] **Step 3: 修复编译问题并验证**

`_DemoPainter` 的 `judgeY` 参数需要适配：在设置页面中传入的是 ratio（0.75），而在 painter 内部需要乘以 canvas 高度。或者改为传入实际像素值。

将 `_DemoPainter` 中 `judgeY` 改为实际像素坐标，在 `_SpeedSettingsPage` 中根据 AspectRatio 容器的实际尺寸计算：

修改 `_DemoPainter` 构造函数中 `judgeY` 改名为 `judgeYRatio`：

```dart
final double judgeYRatio;
```

paint 方法中：
```dart
final actualJudgeY = size.height * judgeYRatio;
canvas.drawLine(Offset(0, actualJudgeY), Offset(w, actualJudgeY), judgePaint);
```

圆圈下落目标也用 `actualJudgeY * 0.7` 替换。

同样修改 `_SpeedSettingsPage` 中传入：
```dart
judgeYRatio: 0.75,
```

Run: `flutter analyze lib/lab/demos/line_demo.dart`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/line_demo.dart
git commit -m "feat(line-demo): add _SpeedSettingsPage with preview animation"
```

---

### Task 3: 修改 `_showSpeedSettings` 使用 Navigator.push

**Files:**
- Modify: `lib/lab/demos/line_demo.dart:400-502`

- [ ] **Step 1: 替换 `_showSpeedSettings` 方法体**

将现有的 `_showSpeedSettings()` 方法（从 `void _showSpeedSettings()` 到 `}` 结束）替换为：

```dart
void _showSpeedSettings() {
  _wasGameRunning = !_isGameOver && !_isCountingDown;

  // 保存快照 + 暂停所有
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
      .push<double>(
    MaterialPageRoute(
      builder: (context) => _SpeedSettingsPage(
        dropDurationMs: _dropDurationMs,
        primaryColor: Theme.of(context).colorScheme.primary,
      ),
    ),
  )
      .then((newSpeed) {
    if (!mounted || _isExiting) return;
    if (newSpeed != null) {
      setState(() => _dropDurationMs = newSpeed);
    }
    _startCountdown();
  });
}
```

这会：
1. 保留现有的暂停/快照逻辑
2. 用 `Navigator.push` 替代 `showModalBottomSheet`
3. 接收返回的速度值并更新
4. 返回后触发倒计时恢复

- [ ] **Step 2: 运行 `flutter analyze` 验证**

Run: `flutter analyze lib/lab/demos/line_demo.dart`
Expected: No issues found

- [ ] **Step 3: 运行 `flutter build web --release` 验证编译**

Run: `flutter build web --release`
Expected: 退出码 0，无编译错误

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/line_demo.dart
git commit -m "feat(line-demo): replace bottom sheet settings with full page"
```

---

### Task 4: 清理旧 BottomSheet 相关代码

**Files:**
- Modify: `lib/lab/demos/line_demo.dart`

- [ ] **Step 1: 检查并移除不再需要的引用**

确认以下内容已被移除（在 Task 3 中已移除）：
- `showModalBottomSheet` 调用
- `StatefulBuilder` 用法
- `setSheetState` 回调

检查 `_showSpeedSettings` 中不再引用 `_isExiting` 条件——设置页面现在有独立返回按钮，不再需要这个判断。但进入设置前的暂停逻辑仍然需要，所以保留 `_stopSpawnTimers` 和快照逻辑。

- [ ] **Step 2: 最终 `flutter analyze` + `flutter build web --release`**

Run:
```bash
flutter analyze lib/lab/demos/line_demo.dart
flutter build web --release
```
Expected: 均无错误

- [ ] **Step 3: Commit**

```bash
git add lib/lab/demos/line_demo.dart
git commit -m "refactor(line-demo): clean up unused bottom sheet code"
```

---

### Task 5: 推送到远程并验证

- [ ] **Step 1: Push 所有 commits**

```bash
git push origin master
```

Expected: 成功推送，GitHub CI 触发 APK 构建
