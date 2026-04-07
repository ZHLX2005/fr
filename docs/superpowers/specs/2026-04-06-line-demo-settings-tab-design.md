# Line Demo 设置页 Tab 化重设计 + 持久化存储

## 概述

将现有速度设置页扩展为 Tab 式设置页，新增"背景样式"设置项。所有设置持久化到 SharedPreferences。

## 持久化存储

使用已有的 SharedPreferences，新增两个 key：

| Key | 类型 | 默认值 | 说明 |
|-----|------|--------|------|
| `line_demo_speed` | `double` | 2500.0 | 下落速度（ms） |
| `line_demo_background` | `int` | 0 | 0=无, 1=网格, 2=线条 |

读取时机：`_LineDemoPageState.initState` 和 `SpeedSettingsPage.initState`。
写入时机：速度滑块变化、背景选择变化时即时写入。

## 数据模型

在 `line_demo_models.dart` 中新增：

```dart
enum BackgroundStyle { none, grid, lines }
```

提供 `int` 索引互转方法（`index` getter 和 `values[index]`）。

## 页面布局

### 整体结构（上下布局）

```
┌──────────────────────────────┐
│ ←                            │
│                              │
│    速度  │  背景样式          │  ← Tab 按钮（预览区外上方）
│                              │
│  ┌────────────────────────┐  │
│  │                        │  │
│  │     预览动画区          │  │  ← 根据选中 tab 显示不同内容
│  │                        │  │
│  └────────────────────────┘  │
│                              │
│      控制区                   │  ← 根据选中 tab 显示不同控件
│                              │
└──────────────────────────────┘
```

### Tab 按钮

- 位置：预览区上方，居中
- 样式：极简线条主义，细线字体（`fontWeight: w200` 未选中 / `w400` 选中）
- 两个文字："速度" 和 "背景样式"，中间用 " | " 分隔
- 选中态：字体颜色为主题色（`primary`），下方有细线指示
- 未选中态：字体颜色为 `onSurfaceVariant` 低透明度

### 速度 Tab 内容

预览区：复用现有落体动画（单圆圈下落 → 炸开 → 循环）。
控制区：复用现有速度滑块，显示 ms 数值，快/慢标签。

### 背景样式 Tab 内容

预览区：静态预览框，显示当前选中背景效果（网格/三竖线/空白），加判定线。
控制区：三个图标按钮横排居中，用 `ToggleButtons` 风格：

| 按钮 | 图标内容 | 说明 |
|------|----------|------|
| 网格 | 方格网格 SVG 图标 | 横竖交叉细线 |
| 线条 | 三条竖线 SVG 图标 | 三条均匀分布竖线 |
| 无 | ✕ 形 SVG 图标 | 表示无背景 |

- 按钮样式：极简线框，`borderRadius` 圆角，边框主题色
- 选中态：边框主题色实线 + 主题色浅底色
- 未选中态：边框 `outlineVariant` 色
- 按钮中央只放图标，不放文字

## 游戏画面背景绘制

在 `GamePainter.paint()` 中，绘制背景元素（在圆圈和判定线之前绘制，确保在最底层）：

### 网格背景（grid）

- 全画面方格网格
- 使用 `Canvas` 循环绘制横竖线
- 线条颜色：`primary.withAlpha(0x1A)`（约 10% 透明度）
- 线宽：0.5px
- 间距：根据画面宽度动态计算，约 20-30rpx

### 三条竖线背景（lines）

- 三条竖线固定在各列中央位置
- 颜色：`primary.withAlpha(0x15)`（约 8% 透明度）
- 线宽：0.5px
- 从画面顶部到底部贯穿
- 列位置：与游戏的三列圆圈 x 坐标一致

### 无背景（none）

不绘制任何背景元素。

## 涉及文件

| 文件 | 改动 |
|------|------|
| `line_demo_models.dart` | 新增 `BackgroundStyle` 枚举 |
| `line_demo_settings.dart` | 重构为 Tab 式页面，增加背景选择 UI，持久化读写 |
| `line_demo_painters.dart` | `GamePainter` 新增 `backgroundStyle` 参数，绘制背景 |
| `line_demo.dart` | 读取持久化的速度和背景设置，传给 `GamePainter` |

## 导航与游戏状态

保持现有行为：
- 游戏页点击设置按钮 → 暂停游戏 → push 设置页
- 设置页返回 → pop → 倒计时恢复游戏
- 返回值：通过 SharedPreferences 持久化，不再依赖 `Navigator.pop(value)` 传值
