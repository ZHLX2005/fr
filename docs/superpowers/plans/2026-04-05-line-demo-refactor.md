# Line Demo 文件拆分 + 设置页布局重设计 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 line_demo.dart 拆分为 4 个文件，设置页布局从左右改为上下（60:40），预览区加浅色主题背景。

**Architecture:** 按职责拆分文件：数据模型、绘制器、设置页、游戏主体。跨文件类去掉 `_` 前缀变为公开。

**Tech Stack:** Flutter/Dart，CustomPainter，AnimationController

---

## File Structure

```
lib/lab/demos/
├── line_demo.dart              # 游戏主体（LineDemo + _LineDemoPage + State）
├── line_demo_models.dart       # 数据类（FallingCircle, ExplodeAnimation, Particle）
├── line_demo_painters.dart     # 绘制器（GamePainter, WaterExitPainter, LineThumbShape）
└── line_demo_settings.dart     # 设置页（SpeedSettingsPage + _DemoPainter）
```

---

### Task 1: 提取数据模型到 `line_demo_models.dart`

**Files:**
- Create: `lib/lab/demos/line_demo_models.dart`
- Modify: `lib/lab/demos/line_demo.dart`

- [ ] **Step 1: 创建 `line_demo_models.dart`**

从 `line_demo.dart` 提取 3 个数据类，去掉 `_` 前缀改为公开：

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 下落中的圆圈
class FallingCircle {
  final AnimationController controller;
  double currentY;
  bool exploded;
  bool missed;

  FallingCircle({
    required this.controller,
    required this.currentY,
  })  : exploded = false,
        missed = false;
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
```

- [ ] **Step 2: 在 `line_demo.dart` 中替换数据类为 import**

删除 `_FallingCircle`（原 line 32-43）、`_ExplodeAnimation`（原 line 46-60）、`_Particle`（原 line 742-752）三个类定义。

在文件顶部添加：
```dart
import 'line_demo_models.dart';
```

在 `_LineDemoPageState` 中全局替换：
- `_FallingCircle` → `FallingCircle`
- `_ExplodeAnimation` → `ExplodeAnimation`
- `_Particle` → `Particle`

- [ ] **Step 3: 运行 `flutter analyze`**

Run: `flutter analyze lib/lab/demos/line_demo.dart lib/lab/demos/line_demo_models.dart`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/line_demo_models.dart lib/lab/demos/line_demo.dart
git commit -m "refactor(line-demo): extract data models to separate file"
```

---

### Task 2: 提取绘制器到 `line_demo_painters.dart`

**Files:**
- Create: `lib/lab/demos/line_demo_painters.dart`
- Modify: `lib/lab/demos/line_demo.dart`

- [ ] **Step 1: 创建 `line_demo_painters.dart`**

提取 `_GamePainter`、`_WaterExitPainter`、`_LineThumbShape`，去掉 `_` 前缀：

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'line_demo_models.dart';

/// 游戏主绘制器：圆圈 + 判定线 + 炸开动画
class GamePainter extends CustomPainter {
  final List<List<FallingCircle>> columns;
  final List<ExplodeAnimation> explodes;
  final Color color;
  final double radius;
  final double screenWidth;
  final double screenHeight;
  final int columnCount;
  final double judgeY;

  GamePainter({
    required this.columns,
    required this.explodes,
    required this.color,
    required this.radius,
    required this.screenWidth,
    required this.screenHeight,
    required this.columnCount,
    required this.judgeY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ... 从原 _GamePainter.paint 宎整复制 ...
  }

  void _paintExplode(Canvas canvas, ExplodeAnimation explode, double w) {
    // ... 从原 _GamePainter._paintExplode 完整复制 ...
  }

  @override
  bool shouldRepaint(GamePainter oldDelegate) => true;
}

/// 水退出动画绘制器
class WaterExitPainter extends CustomPainter {
  final double progress;
  final Color color;

  WaterExitPainter({
    required this.progress,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ... 从原 _WaterExitPainter.paint 完整复制 ...
  }

  @override
  bool shouldRepaint(WaterExitPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// 线条风格 Slider 滑块
class LineThumbShape extends SliderComponentShape {
  final double thumbRadius;

  const LineThumbShape({required this.thumbRadius});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(thumbRadius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final paint = Paint()
      ..color = sliderTheme.thumbColor!
      ..style = PaintingStyle.fill;
    context.canvas.drawCircle(center, thumbRadius, paint);
  }
}
```

完整复制 `paint()` 和辅助方法的代码体，只改类名和方法签名中的类型引用。

- [ ] **Step 2: 在 `line_demo.dart` 中替换绘制器为 import**

删除 `_GamePainter`（~line 759-880）、`_WaterExitPainter`（~line 1238-1348）、`_LineThumbShape`（~line 1350-1378）。

添加 import：
```dart
import 'line_demo_painters.dart';
```

全局替换：
- `_GamePainter` → `GamePainter`
- `_WaterExitPainter` → `WaterExitPainter`
- `_LineThumbShape` → `LineThumbShape`

- [ ] **Step 3: 运行 `flutter analyze`**

Run: `flutter analyze lib/lab/demos/`
Expected: No issues found

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/line_demo_painters.dart lib/lab/demos/line_demo.dart
git commit -m "refactor(line-demo): extract painters to separate file"
```

---

### Task 3: 提取设置页到 `line_demo_settings.dart` + 改上下布局

**Files:**
- Create: `lib/lab/demos/line_demo_settings.dart`
- Modify: `lib/lab/demos/line_demo.dart`

- [ ] **Step 1: 创建 `line_demo_settings.dart`**

提取 `_SpeedSettingsPage`、`_SpeedSettingsPageState`、`_DemoPainter`，其中页面类去掉 `_` 前缀，`_DemoPainter` 保持私有。

关键改动：布局从 `Row`（左右）改为 `Column`（上下），预览区加浅色主题背景。

`build` 方法改为：

```dart
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
              onTap: () => Navigator.of(context).pop(_dropDurationMs),
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: widget.primaryColor,
              ),
            ),
          ),

          // 主内容：上下布局
          Padding(
            padding: EdgeInsets.only(
              top: 56,
              left: 32,
              right: 32,
              bottom: MediaQuery.of(context).padding.bottom + 32,
            ),
            child: Column(
              children: [
                // 上方：预览动画区 (60%)
                Expanded(
                  flex: 6,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 0.6,
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(rpx(16)),
                          border: Border.all(
                            color: widget.primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(rpx(16)),
                          child: AnimatedBuilder(
                            animation: Listenable.merge([_fallController, _explodeController]),
                            builder: (context, _) {
                              return CustomPaint(
                                painter: _DemoPainter(
                                  color: widget.primaryColor,
                                  radius: rpx(20),
                                  judgeYRatio: 0.75,
                                  circleYRatio: _circleYRatio,
                                  showExplode: _showExplode,
                                  explodeProgress: _explodeController.value,
                                  explodeParticles: _explodeParticles,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // 下方：速度控制区 (40%)
                Expanded(
                  flex: 4,
                  child: Column(
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
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
```

其余代码（`_SpeedSettingsPageState` 的动画逻辑、`_DemoPainter`）完整复制，只改类型引用。

需要添加 import：
```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'line_demo_models.dart';
import 'line_demo_painters.dart';
```

注意：`_minDropMs` 和 `_maxDropMs` 不能再引用 `_LineDemoPageState` 的 static const。在 `SpeedSettingsPageState` 中定义自己的常量：

```dart
static const double _minDropMs = 800.0;
static const double _maxDropMs = 4000.0;
```

或者改为从构造函数传入。推荐定义自己的常量（与游戏页保持一致即可）。

- [ ] **Step 2: 在 `line_demo.dart` 中删除设置页相关代码**

删除 `_DemoPainter`（~line 881-1050）、`_SpeedSettingsPage` + `_SpeedSettingsPageState`（~line 988-1235）。

添加 import：
```dart
import 'line_demo_settings.dart';
```

替换引用：
- `_SpeedSettingsPage` → `SpeedSettingsPage`

- [ ] **Step 3: 运行 `flutter analyze` + `flutter build web --release`**

Run:
```bash
flutter analyze lib/lab/demos/
flutter build web --release
```
Expected: No issues, build success

- [ ] **Step 4: Commit**

```bash
git add lib/lab/demos/line_demo_settings.dart lib/lab/demos/line_demo.dart
git commit -m "refactor(line-demo): extract settings page, change layout to top-bottom"
```

---

### Task 4: 最终验证 + Push

- [ ] **Step 1: `flutter analyze` 全量检查**

Run: `flutter analyze lib/lab/demos/`
Expected: No issues found

- [ ] **Step 2: `flutter build web --release`**

Expected: Build success

- [ ] **Step 3: Push**

```bash
git push origin master
```

Expected: 成功推送，GitHub CI 触发
