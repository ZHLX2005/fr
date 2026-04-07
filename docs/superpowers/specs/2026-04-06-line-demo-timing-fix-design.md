# Line Demo 判定时机修正 + 流速控制实现

## 概述

修正音符 spawn 逻辑，使音符在 easeIn 曲线下准确到达 judgeLineRatio 位置，而非屏幕底部。同时将现有 `timingScale` 从单一控制项拆分为**判定缩放**（timingScale）和**流速**（scrollSpeed）两个独立控制项。

## 问题分析

### 当前行为

- `timingScale` 控制：判定窗口大小、血条奖励/惩罚
- `timingScale` **不控制**：音符下落速度、音符 spawn 时机
- spawn 计算：`elapsed >= event.time - dropDuration`
- 这意味着音符在 event.time 前恰好一个 dropDuration 时 spawn，但到达的是屏幕底部（100%高度），而非判定线（75%高度）

### easeIn 曲线特性

`Curves.easeIn` 对应 `y = t²`：

| 动画进度 t | 视觉位置 y | 说明 |
|-----------|-----------|------|
| 0.0 | 0.00 | spawn |
| 0.75 | 0.5625 | 不到判定线 |
| **0.866** | **0.75** | **判定线位置** |
| 1.0 | 1.0 | 屏幕底部 |

**关键发现**：当 judgeLineRatio = 0.75 时，音符在动画 86.6% 时到达判定线，而非 75%。

## 核心修改

### 1. spawn 时机修正

**Before:**
```dart
if (elapsed >= event.time - dropMs) {
  _spawnNote(event);
}
```

**After:**
```dart
// easeIn 曲线下，到达 judgeLineRatio 位置的动画进度
const _easeInToJudgeRatio = 0.866; // sqrt(judgeLineRatio)

// 实际下落时间（受 scrollSpeed 影响）
final actualDropMs = dropMs / scrollSpeed;

// spawn 时机 = event.time - 到达判定线所需时间
if (elapsed >= event.time - (actualDropMs * _easeInToJudgeRatio).round()) {
  _spawnNote(event);
}
```

### 2. 音符动画时长修正

**Before:**
```dart
duration: Duration(milliseconds: _chart!.dropDuration),
```

**After:**
```dart
final actualDropMs = _chart!.dropDuration / scrollSpeed;
duration: Duration(milliseconds: actualDropMs.round()),
```

### 3. auto-miss 判断修正

**Before:**
```dart
final missThreshold = event.time + (_missWindow * _timingScale).round();
```

**After:**
```dart
final scaledMissWindow = (_missWindow * _timingScale).round();
final missThreshold = event.time + scaledMissWindow;
```

### 4. hold 音符完成判断

Hold 音符在 `_spawnNote` 中使用相同的 `actualDropMs` 计算动画时长。

## 流速控制设计

### 控制项拆分

| 控制项 | 参数名 | 范围 | 默认值 | 影响 |
|--------|--------|------|--------|------|
| 判定缩放 | `timingScale` | 0.5x ~ 2.0x | 1.0x | 判定窗口大小、血条奖励/惩罚 |
| 流速 | `scrollSpeed` | 0.5x ~ 2.0x | 1.0x | 音符下落速度、spawn 时机 |

### 流速效果

| scrollSpeed | 实际下落时间 | 效果 |
|-------------|-------------|------|
| 0.5 (慢) | dropDuration / 0.5 = 2× | 音符更早出现，更慢到达判定线 |
| 1.0 (普通) | dropDuration / 1.0 = 1× | 基准 |
| 2.0 (快) | dropDuration / 2.0 = 0.5× | 音符更晚出现，更快到达判定线 |

### 时间线验证（dropDuration=2500ms, scrollSpeed=2.0）

| 时刻 | 事件 |
|------|------|
| elapsed=835 | 音符 spawn（event.time - 2165ms） |
| elapsed≈3000 | 音符到达判定线（2165ms 后） |
| elapsed=3000 | 谱面定义的 hit 时刻 |

### 时间线验证（dropDuration=2500ms, scrollSpeed=0.5）

| 时刻 | 事件 |
|------|------|
| elapsed=-165 | 音符 spawn（event.time - 5000ms） |
| elapsed≈3000 | 音符到达判定线（5000ms × 0.866 = 4330ms 后） |
| elapsed=3000 | 谱面定义的 hit 时刻 |

## 设置页 Tab 结构

```
[ 判定 ] | [ 流速 ] | [ 背景样式 ]
```

### 判定 Tab

- 控制项：`timingScale`（0.5x ~ 2.0x）
- 标签文字："判定缩放"
- 效果描述："越大小窗口越大，越严格奖励/惩罚越高"
- 极慢/极准 标签端

### 流速 Tab

- 控制项：`scrollSpeed`（0.5x ~ 2.0x）
- 标签文字："流速"
- 效果描述："越快音符更晚出现更快到达，越慢更早出现更慢到达"
- 慢/快 标签端
- **演示动画时长** = 2500ms / scrollSpeed

### 背景样式 Tab（已有）

保持现有实现。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `lib/core/line/pages/line_demo_page.dart` | 修正 spawn 逻辑、动画时长、auto-miss；新增 scrollSpeed 状态和持久化 |
| `lib/core/line/settings/line_settings.dart` | 新增 scrollSpeed tab 和相关 UI |
| `lib/core/line/settings/line_settings.dart` | 新增 scrollSpeed 持久化 key |

## 持久化 key

| Key | 类型 | 默认值 | 说明 |
|-----|------|--------|------|
| `line_timing_scale` | `double` | 1.0 | 判定窗口缩放 |
| `line_scroll_speed` | `double` | 1.0 | 流速 |
| `line_background` | `int` | 0 | 背景样式 |

## 实现步骤

1. `line_demo_page.dart` 新增 `_scrollSpeed` 状态和 key
2. `line_demo_page.dart` 修正 `_spawnPendingNotes` 中的 spawn 条件
3. `line_demo_page.dart` 修正 `_spawnNote` 中的动画时长
4. `line_demo_page.dart` 修正 auto-miss 判断（移除多余的 timingScale 应用）
5. `line_settings.dart` 新增流速 tab UI 和持久化
6. 验证时间线正确性
