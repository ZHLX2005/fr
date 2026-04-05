# Line Demo 文件拆分 + 设置页布局重设计

## 概述

将 `line_demo.dart`（1383行）拆分为 4 个文件，并将设置页布局从左右分栏改为上下分栏。

## 文件拆分

| 文件 | 内容 | 职责 |
|------|------|------|
| `line_demo.dart` | `LineDemo`、`_LineDemoPage`、`_LineDemoPageState`、`registerLineDemo()` | 游戏主体 + 入口注册 |
| `line_demo_models.dart` | `FallingCircle`、`ExplodeAnimation`、`Particle` | 数据类（公开，去掉 `_` 前缀） |
| `line_demo_painters.dart` | `GamePainter`、`WaterExitPainter`、`LineThumbShape` | 绘制器（公开，去掉 `_` 前缀） |
| `line_demo_settings.dart` | `SpeedSettingsPage`、`_SpeedSettingsPageState`、`_DemoPainter` | 设置页（页面公开，内部 painter 私有） |

**命名规则：** 跨文件使用的类去掉 `_` 前缀变为公开，文件内部使用的保持私有。

## 设置页布局

从左右（Row 40:60）改为上下（Column 60:40）：

```
┌───────────────────────────────────┐
│ ←                                 │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  动画预览区 (flex:6, 60%)     │ │
│  │  背景：primaryColor alpha 0.05│ │
│  │                              │ │
│  │  AspectRatio(0.6) 圆角线框   │ │
│  │  内部：圆圈下落+炸开循环     │ │
│  └──────────────────────────────┘ │
│                                   │
│  ┌──────────────────────────────┐ │
│  │  控制区 (flex:4, 40%)        │ │
│  │  水平居中                     │ │
│  │  "下落速度" 标签              │ │
│  │  "2500ms" 数值               │ │
│  │  横向滑块                     │ │
│  │  快/慢 标签                   │ │
│  └──────────────────────────────┘ │
└───────────────────────────────────┘
```

**具体改动：**
- `_SpeedSettingsPageState.build` 中 `Row` → `Column`
- 上方 `Expanded(flex:6)` 包裹预览区，加 `Container(color: primaryColor.withAlpha(0.05))` 背景
- 下方 `Expanded(flex:4)` 包裹控制区，内容水平居中 `crossAxisAlignment: CrossAxisAlignment.center`
- 返回按钮保持左上角 `Positioned`
- 其余逻辑不变：动画循环、速度同步、返回值传递
