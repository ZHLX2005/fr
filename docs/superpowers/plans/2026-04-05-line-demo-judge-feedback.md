# Line Demo 判定文字反馈 宯 **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to the implementation plan task-by-task. Use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 点击命中圆圈时在命中位置显示判定文字（Perfect/Great/Good），600ms 淡出** **Architecture:** 在 `_hitCircle()` 中根据得分等级创建反馈数据，存入列表），`GamePainter` 绘制反馈文字。文字用 AnimationController 控制 alpha 淡出。 **Tech Stack:** Flutter/Dart,CustomPainter,AnimationController

---### Task 1: 添加判定反馈数据模型**Files:**
- Modify: `lib/lab/demos/line_demo_models.dart`- [ ] **Step 1: 在 `line_demo_models.dart` 末尾添加 `JudgeFeedback` 类**```dart
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
```- [ ] **Step 2: Run `flutter analyze`**Run: `flutter analyze lib/lab/demos/line_demo_models.dart`
Expected: No issues found- [ ] **Step 3: Commit**
```bash
git add lib/lab/demos/line_demo_models.dart
git commit -m "feat(line-demo): add JudgeFeedback data model"
```

---

### Task 2: 在 `_hitCircle()` 中创建反馈实例

**Files:**
- Modify: `lib/lab/demos/line_demo.dart:50-54` (add feedback 列表)
- Modify: `lib/lab/demos/line_demo.dart:278-333` (修改 `_hitCircle`)

- [ ] **Step 1: 在 `_LineDemoPageState` 中添加反馈列表字段**

在 `_LineDemoPageState` 的 `_explodes` 字段附近（约 line 50-51）添加：

```dart
  final List<JudgeFeedback> _judgeFeedbacks = [];
```- [ ] **Step 2: 修改 `_hitCircle()` 方法，在得分计算后创建反馈**

在 `_hitCircle()` 中，得分计算（约 line 293-304）之后、setState 之前，添加判定文字确定逻辑。将整个 `_hitCircle` 方法中从 `int points;` 判断开始到 `setState` 块替换为：

```dart
    // 计算得分：距离判定线越近越高分
    final judgeY = screenSize.height * _judgeLineRatio;
    final dist = (circle.currentY - judgeY).abs();
    final judgeRange = _rpx(_judgeRangeRpx);

    String judgeText;
    double judgeAlpha;
    int points;
    if (dist <= judgeRange * 0.2) {
      points = 3;
      judgeText = 'Perfect';
      judgeAlpha = 0.6;
    } else if (dist <= judgeRange * 0.5) {
      points = 2;
      judgeText = 'Great';
      judgeAlpha = 0.4;
    } else {
      points = 1;
      judgeText = 'Good';
      judgeAlpha = 0.25;
    }

    // 创建判定文字反馈
    final feedbackController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    final feedback = JudgeFeedback(
      text: judgeText,
      x: centerX,
      y: circle.currentY - radius - 20,
      color: Theme.of(context).colorScheme.primary,
      baseAlpha: judgeAlpha,
      controller: feedbackController,
    );

    setState(() {
      _score += points;
      _judgeFeedbacks.add(feedback);
    });

    // 淡出后移除
    feedbackController.forward().then((_) {
      feedbackController.dispose();
      if (!mounted) return;
      setState(() {
        _judgeFeedbacks.remove(feedback);
      });
    });
```- [ ] **Step 3: 在 `dispose()` 中清理反馈 controllers**

在 `dispose()` 方法中（约 line 144-158），在 `_explodes` 清理循环之后添加：

```dart
    for (final fb in _judgeFeedbacks) {
      fb.controller.dispose();
    }
```- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze lib/lab/demos/line_demo.dart`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/line_demo.dart lib/lab/demos/line_demo_models.dart
git commit -m "feat(line-demo): create judge feedback on circle hit"
```

---

### Task 3: 在 GamePainter 中绘制判定文字

**Files:**
- Modify: `lib/lab/demos/line_demo_painters.dart`

- [ ] **Step 1: 给 `GamePainter` 添加 `judgeFeedbacks` 参数**

在 `GamePainter` 类中（约 line 10-29），添加新字段和构造参数：

在 `final double judgeY;` 之后添加：
```dart
  final List<JudgeFeedback> judgeFeedbacks;
```

在构造函数中 `required this.judgeY,` 之后添加：
```dart
    required this.judgeFeedbacks,
```

- [ ] **Step 2: 在 `paint()` 末尾绘制判定文字**

在 `GamePainter.paint()` 方法中，在炸开动画绘制之后（`for (final explode in explodes)` 循环之后），添加判定文字绘制逻辑：

```dart
    // ── 判定文字反馈 ──
    for (final fb in judgeFeedbacks) {
      final progress = fb.controller.value;
      final alpha = fb.baseAlpha * (1.0 - progress);
      if (alpha <= 0.01) continue;

      final textSpan = TextSpan(
        text: fb.text,
        style: TextStyle(
          fontSize: 10 * screenWidth / 750,
          fontWeight: FontWeight.w300,
          color: fb.color.withValues(alpha: alpha),
          letterSpacing: 2,
        ),
      );
      final tp = TextPainter(
        text: TextSpan(children: [textSpan]),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.layout(maxWidth: screenWidth);
      tp.paint(canvas, Offset(fb.x - tp.width / 2, fb.y - tp.height / 2));
      tp.dispose();
    }
```

- [ ] **Step 3: 更新 `line_demo.dart` 中 GamePainter 构造调用**

在 `line_demo.dart` 的 `build()` 方法中找到 `GamePainter(` 构造调用（约 line 510-528），添加 `judgeFeedbacks` 参数：

在 `judgeY: judgeY,` 之后添加：
```dart
                      judgeFeedbacks: _judgeFeedbacks,
```

- [ ] **Step 4: Run `flutter analyze`**

Run: `flutter analyze lib/lab/demos/`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/lab/demos/line_demo_painters.dart lib/lab/demos/line_demo.dart
git commit -m "feat(line-demo): render judge feedback text in GamePainter"
```

---

### Task 4: 最终验证

- [ ] **Step 1: Run `flutter analyze lib/lab/demos/`**

Expected: No issues from our files

- [ ] **Step 2: Run `flutter build web --release`**

Expected: Build success

- [ ] **Step 3: Push**

```bash
git push origin master
```
