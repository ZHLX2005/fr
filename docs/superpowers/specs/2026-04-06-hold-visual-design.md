# Hold 音符视觉设计规范

> **日期：** 2026-04-06
> **状态：** 已确认
> **风格：** 霓虹脉冲 (Neon Pulse)

---

## 1. 概述

重新设计 Hold 音符的视觉表现，增加按住过程中的动态反馈和完成时的粒子爆发效果。整体风格为霓虹发光效果，颜色跟随游戏主题色（`colorScheme.primary`）。

---

## 2. 视觉设计

### 2.1 条形尺寸

| 属性 | 值 | 说明 |
|------|-----|------|
| 宽度 | `radius × 1.6` | 默认 radius=20 → 条宽 32px |
| 头部圆圈半径 | `radius` | 判定线位置的头部标记 |
| 最小高度 | 0（未按下时仅有轮廓） | — |

### 2.2 颜色方案

使用游戏主题色 `colorScheme.primary`，组件自适配：

| 元素 | 颜色 |
|------|------|
| 条形主体 | `primary` + 发光阴影 (`shadowBlur: 15 * holdProgress`) |
| 条形边缘 | `primary` 亮度 +30% 的淡色 |
| 粒子 | `primary` 亮度 +20% 的淡色 |
| 脉冲/闪烁 | `primary` 原色 |

### 2.3 透明度规则

```
状态              透明度计算
─────────────────────────────────────────────
未按（待按下）    α = 0.5（整个条）
按住中           α = 0.5 × (1 - holdProgress × 0.8)
                 按住越久，整体越透明（底部区域保持较实）
判定消失         α = 0.5 × (1 - holdFadeOut)
                 从 0.5 渐变到 0
```

### 2.4 状态定义

| 状态 | holdProgress | holdFadeOut | 说明 |
|------|-------------|-------------|------|
| `idle` | 0 | 0 | 未按下，只有淡色轮廓 |
| `holding` | 0.0 → 1.0 | 0 | 玩家正在按住，进度从 0 增长到 1 |
| `judged` | 保持按下时的值 | 0.0 → 1.0 | 判定成功，启动 fade-out 动画 |
| `missed` | 保持按下时的值 | 0.0 → 1.0 | 判定失败（提前松手或超时），启动 fade-out |

---

## 3. 动画设计

### 3.1 按住中动画（Neon Pulse Fill）

- **条形填充**：底部实心，向上随 `holdProgress` 增长而填充。整体有霓虹发光效果，`shadowBlur` 强度随进度增加（`15 × holdProgress`）。
- **脉冲效果**：按住期间，条形有微弱的呼吸脉冲（alpha 在基础值 ±5% 范围内波动），频率约 2Hz。
- **边缘高光**：条形左/右边沿有一条亮线，alpha = `0.6 + 0.3 × holdProgress`。

### 3.2 完成消失动画（Neon Burst & Flicker）

触发条件：`holdProgress >= 1.0`（判定成功）

**时序（总时长约 400ms）：**

| 时间点 | 效果 |
|--------|------|
| 0ms | 头部圆圈爆发 **8 个粒子**，向四周扩散，带重力下落 |
| 0-100ms | 条形开始**快速闪烁**（alpha 在 0.3-0.7 之间震荡，频率 30Hz） |
| 100-400ms | 闪烁减弱，条形整体 **ease-out 渐隐消失** |

**粒子参数：**
```
数量：8 个
初始速度：40-70 px/s，随机方向
重力：80 px/s²
生命周期：400ms
颜色：primary 亮度 +20%
尺寸：2-4px 圆形
```

---

## 4. 组件变更

### 4.1 `FallingNote` 模型（line_models.dart）

新增字段：

```dart
double holdFadeOut;     // 判定后渐隐进度 0~1（默认 0）
```

### 4.2 `GamePainter._paintHoldNote`（line_page.dart）

重写绘制逻辑：

```
未按住：
  → 绘制双线轮廓（alpha=0.35）
  → 绘制空心头部圆圈（alpha=0.5）

按住中：
  → 绘制实心填充（底部到 holdProgress 对应高度）
  → 绘制 shadowBlur 发光（15 × holdProgress px）
  → 绘制左右边缘高光线
  → 绘制顶部前沿亮条
  → 绘制实心头部圆圈（alpha 随进度微变）

判定消失中（holdFadeOut > 0）：
  → 条形闪烁 alpha = (0.5 + 0.2 × sin(holdFadeOut × 30π)) × (1 - holdFadeOut)
  → 粒子每帧更新位置和 alpha
  → holdFadeOut 从 0 增长到 1（300ms ease-out）
  → holdFadeOut = 1 时从 column 中移除
```

### 4.3 粒子系统

`GamePainter` 新增 `_paintParticles` 方法，负责绘制完成时爆发的粒子。粒子数据存储在 `FallingNote` 中（新增 `List<Particle>? holdParticles` 字段）或通过 `ExplodeAnimation` 复用已有粒子系统。

---

## 5. 实现文件

| 文件 | 变更 |
|------|------|
| `lib/core/line/models/line_models.dart` | `FallingNote` 新增 `holdFadeOut` 字段 |
| `lib/core/line/pages/line_page.dart` | 重写 `_paintHoldNote`；新增粒子绘制逻辑；`GamePainter.shouldRepaint` 返回 true |

---

## 6. 自检清单

- [ ] 霓虹发光效果：按住时 shadowBlur 随 holdProgress 增加
- [ ] 脉冲呼吸：按住期间有条形 alpha 的微弱波动
- [ ] 完成粒子：8 个粒子从头部爆发，带重力扩散
- [ ] 闪烁消失：完成后先快速闪烁，再 ease-out 渐隐
- [ ] 颜色跟随主题：`colorScheme.primary` 作为主色
- [ ] 宽度：条宽 = `radius × 1.6`
- [ ] 透明度规则与设计一致
- [ ] `holdFadeOut` 正确驱动 fade-out 时长 300ms
