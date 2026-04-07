# Hold 音符视觉实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Hold 音符的霓虹脉冲视觉风格：按住中实心填充+发光效果，完成时粒子爆发+闪烁消失

**Architecture:** 在 `GamePainter._paintHoldNote` 中重写 hold 条绘制逻辑，使用 `shadowBlur` 实现霓虹发光，按住进度驱动填充高度，完成时触发闪烁和粒子效果。`FallingNote` 模型新增 `holdFadeOut` 字段驱动渐隐动画。

**Tech Stack:** Flutter (CustomPainter), 无新增依赖

---

## 文件变更概览

| 文件 | 变更 |
|------|------|
| `lib/core/line/models/line_models.dart` | `FallingNote` 新增 `holdFadeOut` 字段 |
| `lib/core/line/pages/line_page.dart` | 重写 `_paintHoldNote` 方法；新增粒子绘制；`shouldRepaint` 返回 `true` |

---

## Task 1: `FallingNote` 模型新增 `holdFadeOut` 字段

**Files:**
- Modify: `lib/core/line/models/line_models.dart:93-103`

- [ ] **Step 1: 在 `FallingNote` 构造函数初始化列表添加 `holdFadeOut = 0.0`**

找到 `FallingNote` 构造函数，在初始化列表末尾添加：

```dart
FallingNote({
  required this.event,
  required this.controller,
  required this.currentY,
})  : judged = false,
        removeMe = false,
        holding = false,
        holdProgress = 0.0,
        holdJudgeDiff = 0,
        holdPressTime = 0,
        holdFadeOut = 0.0;  // 新增
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/line/models/line_models.dart
git commit -m "feat(line): add holdFadeOut field to FallingNote"
```

---

## Task 2: 重写 `_paintHoldNote` — 基础绘制

**Files:**
- Modify: `lib/core/line/pages/line_page.dart:175-214`

- [ ] **Step 1: 替换整个 `_paintHoldNote` 方法**

找到 `_paintHoldNote` 方法（从 `void _paintHoldNote(` 开始），替换为以下完整实现：

```dart
void _paintHoldNote(Canvas canvas, double cx, FallingNote note) {
  if (note.currentY < -radius * 2) return;

  final headY = note.currentY;

  // tail 在 head 上方（Y 值更小）
  final travelPerMsActual = screenHeight * scrollSpeed / dropDuration;
  final tailOffset = travelPerMsActual * note.event.holdDuration!;
  final tailY = headY - tailOffset;

  // 条宽度
  final barWidth = radius * 1.6;

  // 填充高度计算
  final totalHeight = headY - tailY;
  final fillBottom = headY;
  final fillTop = tailY + totalHeight * (1 - note.holdProgress);

  // 透明度计算
  double alpha;
  if (note.holdFadeOut > 0) {
    // 判定后：从 0.5 渐变到 0
    alpha = 0.5 * (1.0 - note.holdFadeOut);
  } else if (note.holding) {
    // 按住中：从 0.5 线性减小到 0
    alpha = 0.5 * (1.0 - note.holdProgress * 0.8);
  } else {
    alpha = 0.5;
  }
  if (alpha < 0.01) return;

  // ── 未填充区域（轮廓）──
  final outlinePaint = Paint()
    ..color = color.withValues(alpha: 0.35)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  canvas.drawRect(
    Rect.fromLTWH(cx - barWidth / 2, tailY, barWidth, totalHeight),
    outlinePaint,
  );

  // ── 填充区域（按住中才绘制）──
  if (note.holding || note.holdProgress > 0) {
    // 霓虹发光
    final glowAlpha = alpha * 0.6;
    final glowBlur = 15.0 * note.holdProgress;

    // 发光层（shadow）
    final glowPaint = Paint()
      ..color = color.withValues(alpha: glowAlpha)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);
    canvas.drawRect(
      Rect.fromLTWH(cx - barWidth / 2, fillTop, barWidth, fillBottom - fillTop),
      glowPaint,
    );

    // 实心填充
    final fillPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx - barWidth / 2, fillTop, barWidth, fillBottom - fillTop),
      fillPaint,
    );

    // 左边缘高光线
    final edgePaint = Paint()
      ..color = Color.lerp(color, Colors.white, 0.4)!.withValues(alpha: (0.6 + 0.3 * note.holdProgress) * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(cx - barWidth / 2, fillTop),
      Offset(cx - barWidth / 2, fillBottom),
      edgePaint,
    );

    // 顶部前沿亮条
    if (note.holdProgress > 0 && note.holdProgress < 1) {
      final edgeAlpha = alpha * (0.7 + 0.3 * note.holdProgress);
      final frontPaint = Paint()
        ..color = Colors.white.withValues(alpha: edgeAlpha.clamp(0.0, 1.0))
        ..style = PaintingStyle.fill;
      canvas.drawRect(
        Rect.fromLTWH(cx - barWidth / 2, fillTop - 1.5, barWidth, 3),
        frontPaint,
      );
    }
  }

  // ── 头部圆圈 ──
  final circlePaint = Paint()
    ..color = color.withValues(alpha: alpha.clamp(0.0, 1.0))
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  canvas.drawCircle(Offset(cx, headY), radius, circlePaint);
}
```

- [ ] **Step 2: 提交**

```bash
git add lib/core/line/pages/line_page.dart
git commit -m "feat(line): rewrite _paintHoldNote with neon glow effect"
```

---

## Task 3: 添加完成闪烁和粒子爆发效果

**Files:**
- Modify: `lib/core/line/pages/line_page.dart`

- [ ] **Step 1: 在 `GamePainter` 类中添加粒子绘制辅助方法**

在 `_paintHoldNote` 方法之后添加：

```dart
void _paintHoldNoteParticles(Canvas canvas, double cx, double headY, double alpha, double fadeOut) {
  if (fadeOut <= 0) return;

  // 闪烁效果：alpha 在基础值 ±20% 范围内震荡，频率随 fadeOut 加快
  final flickerFreq = 30.0; // Hz
  final flicker = 0.8 + 0.2 * math.sin(fadeOut * math.pi * flickerFreq);
  final flickerAlpha = alpha * flicker * (1.0 - fadeOut);
  if (flickerAlpha < 0.01) return;

  // 粒子：8 个，从头部爆发
  // 使用一个固定种子确保粒子方向稳定
  final particleCount = 8;
  for (int i = 0; i < particleCount; i++) {
    final baseAngle = (2 * math.pi * i / particleCount);
    final speed = 40.0 + (i % 3) * 10.0; // 40-60 px/s
    final vx = math.cos(baseAngle) * speed * (1 - fadeOut * 0.5);
    final vy = math.sin(baseAngle) * speed * (1 - fadeOut * 0.5) - 20 * fadeOut; // 向上偏移
    final px = cx + vx * fadeOut * 0.3;
    final py = headY + vy * fadeOut * 0.3;
    final particleAlpha = (1 - fadeOut) * 0.8;
    final particleSize = 2.0 + (i % 2) * 1.5;

    if (particleAlpha > 0.01) {
      final pPaint = Paint()
        ..color = Color.lerp(color, Colors.white, 0.3)!.withValues(alpha: particleAlpha)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), particleSize * (1 - fadeOut * 0.3), pPaint);
    }
  }
}
```

- [ ] **Step 2: 在 `_paintHoldNote` 末尾添加粒子绘制调用**

在 `_paintHoldNote` 方法的 `canvas.drawCircle(Offset(cx, headY), radius, circlePaint);` 之后添加：

```dart
// ── 粒子爆发（完成时）──
if (note.holdFadeOut > 0) {
  _paintHoldNoteParticles(canvas, cx, headY, alpha, note.holdFadeOut);
}
```

- [ ] **Step 3: 在 `_paintHoldNote` 的闪烁逻辑中集成 flickerAlpha**

找到透明度计算部分的 `判定后` 逻辑，修改为：

```dart
if (note.holdFadeOut > 0) {
  // 闪烁 alpha
  final flickerFreq = 30.0;
  final flicker = 0.5 + 0.5 * math.sin(note.holdFadeOut * math.pi * flickerFreq);
  alpha = 0.5 * (1.0 - note.holdFadeOut) * flicker;
}
```

- [ ] **Step 4: 提交**

```bash
git add lib/core/line/pages/line_page.dart
git commit -m "feat(line): add flicker and particle burst to hold completion"
```

---

## Task 4: 确保 `shouldRepaint` 返回 `true`

**Files:**
- Modify: `lib/core/line/pages/line_page.dart:304`

- [ ] **Step 1: 确认 `shouldRepaint` 返回 `true`**

当前实现已经是 `return true;`，无需修改。如果不是，改为：

```dart
@override
bool shouldRepaint(GamePainter oldDelegate) => true;
```

- [ ] **Step 2: 提交（无变更则跳过）**

---

## Task 5: 验证

- [ ] **Step 1: 运行应用**

```bash
flutter run
```

- [ ] **Step 2: 进入游戏，找到 hold 音符（3-5 秒处），观察：**
  - 未按：淡色轮廓 + 空心圆圈
  - 按住：底部实心向上填充，边缘发光，顶部有亮条
  - 完成：粒子爆发 + 闪烁 + 渐隐消失

- [ ] **Step 3: 提交**

```bash
git add -A
git commit -m "feat(line): verify hold neon pulse visual effect"
```

---

## 自检清单

- [ ] spec 中每个需求都有对应 task
- [ ] 无 placeholder (TBD/TODO)
- [ ] `FallingNote.holdFadeOut` 字段已添加且初始化为 0.0
- [ ] 条宽度 = `radius × 1.6`
- [ ] 霓虹发光使用 `MaskFilter.blur` + `shadowBlur = 15 × holdProgress`
- [ ] 粒子 8 个，从头部爆发，带简单运动
- [ ] 闪烁频率约 30Hz，fadeOut ease-out 消失
- [ ] `shouldRepaint` 返回 `true`
