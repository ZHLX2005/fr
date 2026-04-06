# Line Demo 判定文字反馈

## 概述

点击命中圆圈时，在命中位置显示判定文字反馈（Perfect/Great/Good），600ms 后淡出消失。极简线条风格。

## 判定等级

| 等级 | 条件 | 文字 | 颜色透明度 |
|------|------|------|-----------|
| Perfect | `dist <= judgeRange * 0.2` | "Perfect" | primaryColor alpha 0.6 |
| Great | `dist <= judgeRange * 0.5` | "Great" | primaryColor alpha 0.4 |
| Good | 其余 | "Good" | primaryColor alpha 0.25 |

## 视觉样式

- 字重：`FontWeight.w100`
- 字号：`12rpx`（小，不抢眼）
- 位置：圆圈命中位置正上方偏移 `8rpx`
- 动画：出现时 alpha 从初始值线性降到 0，持续 600ms
- 使用现有 `_GamePainter` 绘制（Canvas.drawText），不需要额外 Widget

## 实现方式

1. 新增 `JudgeFeedback` 数据类到 `line_demo_models.dart`：
   ```dart
   class JudgeFeedback {
     final String text;
     final double x;
     final double y;
     final double initialAlpha;
     final AnimationController controller;
   }
   ```

2. 在 `_LineDemoPageState` 中维护 `List<JudgeFeedback> _judges` 列表

3. `_hitCircle()` 中创建 `JudgeFeedback`，添加到 `_judges`，controller forward 完成后移除

4. `GamePainter` 新增 `judges` 参数，在 `paint()` 中绘制判定文字

5. `build()` 中将 `_judges` 的 controller 加入 `allControllers` 以触发重绘

## 数据流

```
点击命中 → _hitCircle()
         → 判定等级(Perfect/Great/Good)
         → 创建 JudgeFeedback(controller: 600ms)
         → 加入 _judges 列表
         → AnimatedBuilder 触发重绘
         → GamePainter.paint() 绘制文字
         → 600ms 后 controller 完成
         → 从 _judges 移除 + dispose
```

## 改动范围

- `line_demo_models.dart`：新增 `JudgeFeedback` 类
- `line_demo.dart`：`_hitCircle()` 中创建反馈、维护列表、传入 painter
- `line_demo_painters.dart`：`GamePainter` 新增 judges 参数 + 绘制文字
