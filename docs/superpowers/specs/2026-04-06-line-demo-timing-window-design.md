# line_demo 判定窗口缩放设计

## 背景问题

当前 `dropDurationMs`（用户可调速度）同时控制两个无关的维度：

1. **音符下落距离** — 从屏幕顶部到判定线的像素距离
2. **音符飞行时间** — 从 spawn 到判定线的时间

当 `dropDurationMs` 被调大时（如 3549ms > 谱面设计值 2500ms），产生矛盾：

- 音符 spawn 时刻 = `event.time - dropMs` （可能为负，游戏开始前）
- 音符实际到达判定线时刻 ≈ `dropMs × 某比例`
- 玩家期望的 hit 时刻 = `event.time`
- auto-miss 在音符视觉到达前就被触发了

**简言之：速度变化导致音符实际到达判定线的时刻和谱面定义的 `event.time` 严重错位。**

## 设计目标

- 移除速度与判定的耦合
- 用户可调节"容错程度"，不改变谱面设计意图
- 在设置页面可视化判定区域，帮助用户理解

## 核心设计

### 概念替换

| 当前设计 | 新设计 |
|---------|--------|
| `dropDurationMs` 用户滑杆 (800~4000ms) | `timingScale` 用户滑杆 (0.5x~2.0x) |
| 控制下落速度 | 控制判定窗口缩放 |
| 影响音符飞行时间 | 只影响判定容错范围 |
| 谱面 `dropDuration` 被用户值覆盖 | 谱面 `dropDuration` 固定为下落时间 |

### 判定窗口计算

基础窗口（代码常量）：
- Perfect: 50ms
- Great: 100ms
- Good: 150ms
- Miss: 200ms

用户调节 `timingScale` 后的实际窗口：
```
实际窗口 = 基础窗口 × timingScale
```

### 游戏区行为

- 下落时间 = 谱面 `dropDuration`（固定，不受用户调节影响）
- 音符 spawn 时刻 = `event.time - dropDuration`
- 判定时使用缩放后的窗口
- **不显示判定区域可视化**，保持游戏风格

### 设置页面演示区

- 演示区显示一个圆圈从顶部下落到判定线
- 圆圈下落时间 = 谱面 `dropDuration`（固定）
- **在判定线上方绘制 4 层半透明区域带**，对应 Perfect/Great/Good/Miss
- 圆圈经过区域时视觉反馈当前所处窗口
- 用户拖动滑杆时，区域带范围实时缩放

## UI 变更

### 设置页面 (`line_settings.dart`)

**Tab 标签：** "速度" → "判定"

**滑杆：**
- 标签："判定缩放"
- 范围：0.5 ~ 2.0
- 默认值：1.0
- 显示：`1.0x` 格式

**演示区增强：**
- 新增 `_DemoPainter` 中绘制判定区域带
- 4 层区域以半透明色块呈现，颜色从内到外渐变（Perfect 最亮，Miss 最暗）

### 游戏页面 (`line_demo_page.dart`)

- 移除 `_dropDurationMs` 用户控制相关代码
- 从 `ChartData.dropDuration` 读取固定下落时间
- 判定窗口乘以 `timingScale`
- 持久化 key：`lineTimingScaleKey = 'line_demo_timing_scale'`

### 持久化 key 变更

| Key | 变更 |
|-----|------|
| `lineSpeedKey` | 删除 |
| `lineTimingScaleKey` | 新增，存储 `timingScale` |
| `lineBackgroundKey` | 保留 |

## 数据流

```
ChartData.dropDuration (固定)
        ↓
    下落动画 duration
        ↓
spawn 时刻 = event.time - dropDuration
        ↓
游戏运行时判定
        ↓
用户 timingScale → 窗口缩放
```

## 涉及文件

1. `lib/core/line/settings/line_settings.dart` — 替换速度滑杆为窗口缩放滑杆，增强 `_DemoPainter`
2. `lib/core/line/pages/line_demo_page.dart` — 移除速度控制，应用 scale 到判定窗口
3. `docs/superpowers/specs/2026-04-06-line-demo-timing-window-design.md` — 本文档
