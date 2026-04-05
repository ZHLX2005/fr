# Line Demo 音游玩法扩展设计

## 概述

将现有下落点击游戏扩展为完整音游：新增三种音符类型（点击/长按/滑动）、血条系统、JSON 谱面加载。由谱面驱动音符生成，替代现有随机生成机制。

## 谱面数据

### JSON 格式

文件位置：`assets/charts/<name>.json`

```json
{
  "name": "谱面名称",
  "bpm": 120,
  "dropDuration": 2500,
  "notes": [
    { "time": 1000, "column": 1, "type": "tap" },
    { "time": 2000, "column": 0, "type": "hold", "holdDuration": 600 },
    { "time": 3000, "column": 2, "type": "slide", "direction": "up" }
  ]
}
```

注释行（`"=== ... ==="` 格式的纯字符串）在解析时被忽略。

### NoteEvent 字段

| 字段 | 类型 | 必需 | 说明 |
|------|------|------|------|
| `time` | int | 是 | 音符到达判定线的时间（ms），从游戏开始计时 |
| `column` | int | 是 | 列号 0/1/2 |
| `type` | string | 是 | "tap" / "hold" / "slide" |
| `holdDuration` | int | 仅 hold | 长按持续时间（ms） |
| `direction` | string | 仅 slide | "up" / "down" / "left" / "right" |

### 测试谱面

`assets/charts/test_chart.json`：151 秒，约 200 个音符，6 个阶段渐进难度。

## 数据模型

### 新增枚举

```dart
enum NoteType { tap, hold, slide }
enum SlideDirection { up, down, left, right }
```

### NoteEvent

```dart
class NoteEvent {
  final int time;             // ms
  final int column;           // 0/1/2
  final NoteType type;
  final SlideDirection? direction;  // 仅 slide
  final int? holdDuration;          // 仅 hold，ms
}
```

提供 `fromJson(Map<String, dynamic>)` 工厂构造函数。解析时跳过非 Map 条目（注释行）。

### FallingNote（替代 FallingCircle）

```dart
class FallingNote {
  final NoteEvent event;
  final AnimationController controller;
  double currentY;
  bool judged;           // 是否已判定
  bool holding;          // 仅 hold：正在被按住
  double holdProgress;   // 仅 hold：按住进度 0~1
}
```

## 主时钟 & 音符生成

### 主时钟

- 游戏开始（倒计时结束后）启动 `_gameElapsedMs`，从 0 累加
- 使用 `Stopwatch` 精确计时，每帧通过 `_fallController` listener 读取
- 谱面所有音符按 `time` 升序排列

### 音符生成逻辑

```
对于谱面中每个 NoteEvent：
  当 gameElapsedMs >= note.time - dropDuration 时：
    创建 FallingNote，controller duration = dropDuration
    从顶部开始下落
```

不再使用 `Timer` 随机生成。改为遍历排序后的谱面列表，按时间触发。

## 判定系统

### 判定窗口

以音符 `event.time` 为基准，计算操作时刻与预期时刻的偏差：

| 判定 | 偏差范围 | 得分 | 血条变化 |
|------|----------|------|----------|
| Perfect | <= 50ms | 3 | +5% |
| Great | <= 100ms | 2 | +2% |
| Good | <= 150ms | 1 | 0% |
| Miss | > 150ms 或未操作 | 0 | -15% |

### Tap（点击）

- 玩家点击某列 → 找该列离判定线最近的未判定 `tap` 音符
- 计算操作时刻 vs `note.event.time` 的偏差，判定等级
- 判定成功：触发炸开动画 + 判定文字反馈
- 音符到达判定线后超过 150ms 未被点击：自动 Miss

### Hold（长按）

- 音符头部到达判定线附近（Good 范围内）时，玩家在该列按下并保持
- 按住期间：长条在判定线区域发光（亮度提高），`holdProgress` 从 0 增长到 1
- `holdProgress` 增长速率 = `1.0 / (holdDuration / 16.6ms)`（每帧）
- 当 `holdProgress >= 1.0` 且从头到尾未松手：判定成功，按头部命中精度定 Perfect/Great/Good
- 中途松手：立即 Miss
- 音符头部穿过判定线 150ms 未按下：Miss

### Slide（滑动）

- 音符到达判定线附近时，检测滑动手势方向
- 通过 `GestureDetector.onPanEnd` 获取速度向量，计算主方向（上下左右）
- 方向匹配 `event.direction`：判定成功
- 方向不匹配或超时：Miss
- 不需要先点击，直接在判定区域滑动即可

## 血条

### 数据

```dart
double _health = 1.0;  // 0.0 ~ 1.0
```

### 规则

- 初始满血（1.0）
- Perfect: +0.05, Great: +0.02, Good: 0, Miss: -0.15
- 上限 clamp 1.0，下限到 0.0 则 Game Over
- 去掉现有的 `_missCount` 和 3 Miss 规则

### 绘制

- 位置：屏幕右侧，距右边缘 12px
- 宽度：8px，高度：从顶部 60px 延伸到底部 25%（判定线位置）
- 背景：深色半透明（`surface.withAlpha(0x33)`）
- 前景颜色：
  - > 50%：绿色（`Colors.green.shade400`）
  - 30-50%：黄色（`Colors.orange.shade400`）
  - < 30%：红色（`Colors.red.shade400`）
- 圆角：4px
- 填充方向：从底部向上

## 绘制变化

### GamePainter 新增内容

**Tap 音符**：保持现有圆圈样式。

**Hold 音符**：
- 头尾各一个圆圈（与 tap 同样式）
- 中间连接一条半透明矩形带，宽度 = 圆圈直径 * 0.6
- 正在被按住时，判定线区域内的部分亮度提高（alpha 从 0.3 提升到 0.6）
- holdProgress 用一个小填充条显示在长条内部（从底部向上填充）

**Slide 音符**：
- 圆圈与 tap 相同
- 圆圈内部绘制方向箭头（三角形），alpha 0.5
- 箭头方向：up=向上三角, down=向下, left=向左, right=向右

**血条**：在所有游戏元素之前绘制（最底层）。

### 爆炸粒子效果

保持现有机制。Tap 成功、Hold 成功（尾部）、Slide 成功都触发相同的炸开动画。

## 手势检测

替换现有 `GestureDetector.onTapUp`，改为：

```dart
GestureDetector(
  onTapUp: _handleTap,        // tap 音符
  onPanEnd: _handleSwipe,     // slide 音符（检测方向）
  onLongPressStart: ...       // hold 按下
  onLongPressEnd: ...         // hold 松手
)
```

实际上需要更细致的手势管理：
- `onTapUp`：处理 tap 判定
- `onPanStart` + `onPanUpdate` + `onPanEnd`：检测滑动方向，处理 slide
- 按下列区域 → 检查是否有 hold 音符需要按住
- 需要在列级别追踪按住状态

## 涉及文件

| 文件 | 改动 |
|------|------|
| `line_demo_models.dart` | 新增 NoteType, SlideDirection, NoteEvent, FallingNote；保留 Particle, JudgeFeedback, BackgroundStyle；废弃 FallingCircle, ExplodeAnimation 保留 |
| `line_demo_painters.dart` | GamePainter 重绘三种音符 + 血条；新增箭头绘制、长条绘制、血条绘制 |
| `line_demo.dart` | 重写游戏逻辑：主时钟、谱面加载、三种判定、血条、手势 |
| `line_demo_settings.dart` | 保持不变（速度和背景设置仍然有效） |
| `assets/charts/test_chart.json` | 新增测试谱面文件 |

## 设置页影响

速度设置仍然控制 `dropDuration`，影响音符从顶部到判定线的时间。背景设置不变。设置持久化机制不变。

## 谱面加载

在 `pubspec.yaml` 中注册 assets 目录：
```yaml
flutter:
  assets:
    - assets/charts/
```

游戏启动时通过 `rootBundle.loadString('assets/charts/test_chart.json')` 加载谱面。以后可以扩展为多谱面选择。
