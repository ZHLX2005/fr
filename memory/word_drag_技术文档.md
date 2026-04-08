# WordDrag 模块技术文档

## 概述

WordDrag 是一个模仿 photoo (NativeVoiceLikeActivity.kt) 实现的单词拖拽背单词 Flutter 模块。

## 核心文件结构

```
lib/core/word_drag/
├── models/word.dart                    # 单词数据模型
├── providers/
│   ├── word_drag_state.dart            # 状态数据类
│   ├── word_drag_notifier.dart          # 状态管理器
│   └── draggable_word_card_controller.dart
├── widgets/
│   ├── draggable_word_card.dart        # 可拖拽单词卡片
│   ├── category_drop_row.dart          # 分类桶选择行
│   └── word_card_content.dart          # 卡片内容
├── pages/
│   ├── word_drag_page.dart             # 主页面
│   └── word_detail_page.dart           # 详情页
└── word_drag.dart                      # 导出入口
```

## 核心交互对照表

| 交互 | Kotlin 回调 | Dart 回调 | 阈值 |
|------|------------|-----------|------|
| 上滑 | onSwipeUp() | onSwipeUp | 160px |
| 左滑 | onSwipeLeft() | onSwipeLeft | 160px |
| 右滑 | onSwipeRight() | onSwipeRight | 160px |
| 下滑>300px | 显示 FolderDropRow | 显示 CategoryDropRow | 300px |
| 下滑>420px | 进入文件夹模式 | 进入文件夹模式 | 420px |
| 快速滑动 | velocity > 800 | velocity < -800 | 800 |

## DraggableCard 参数对比

### 滑动阈值
- threshold = 160f ✅
- folderModeThreshold = 420f ✅
- velocityThreshold = 800f ✅
- actionIndicatorFolderThreshold = 150f ✅ (2026-04-09 修复)

### Action Indicator 阈值
| 指示器 | Kotlin | Dart | 状态 |
|--------|--------|------|------|
| folder | 150f | 150 | ✅ |
| like | 100f | 100 | ✅ |
| delete | 100f | 100 | ✅ |
| skip | 100f | 100 | ✅ |

### 堆叠效果
- scaleValue = 1f - (effectiveStackIndex * 0.04f) ✅
- yOffsetValue = effectiveStackIndex * 15dp ✅

### 堆叠动画 (2026-04-09 修复)
```kotlin
// Kotlin - 使用 animateFloatAsState 进行堆叠过渡动画
val scale by animateFloatAsState(
    targetValue = scaleValue,
    animationSpec = spring(stiffness = 350f, dampingRatio = 0.75f)
)
val yOffset by animateDpAsState(
    targetValue = yOffsetValue,
    animationSpec = spring(stiffness = 350f, dampingRatio = 0.75f)
)
```

```dart
// Dart - 使用 AnimationController + SpringSimulation
// didUpdateWidget 中当 stackIndex 变化时触发动画
final spring = SpringDescription(
  mass: 1.0,
  stiffness: 350.0,
  damping: 0.75 * 2 * sqrt(350.0), // ≈ 28.07
);
_stackScaleController.animateWith(SpringSimulation(spring, _stackScale, targetScale, 0));
_stackYOffsetController.animateWith(SpringSimulation(spring, _stackYOffset, targetYOffset, 0));
```
✅ 一致

### 动态缩放
```kotlin
// Kotlin
val dynamicScale = when {
    offsetY.value < 0 -> (1f + offsetY.value / 1000f).coerceAtLeast(0.9f)
    offsetY.value > 0 -> (1f - offsetY.value / 1000f).coerceAtLeast(0.5f)
    else -> 1f
}
```

```dart
// Dart
double get _dynamicScale {
    if (_offsetY < 0) {
      return (1.0 + _offsetY / 1000).clamp(0.9, 1.0);
    } else if (_offsetY > 0) {
      return (1.0 - _offsetY / 1000).clamp(0.5, 1.0);
    }
    return 1.0;
}
```
✅ 完全一致

### 回弹动画
```kotlin
spring(stiffness = 2000f, dampingRatio = 0.85f)
```

```dart
final spring = SpringDescription(
    mass: 1.0,
    stiffness: 2000.0,
    damping: 76.0, // 0.85 * 2 * sqrt(2000)
);
```
✅ 一致

### 吸进动画
```kotlin
launch { exitScale.animateTo(0.1f, tween(250)) }
launch { alphaAnim.animateTo(0f, tween(250)) }
launch { offsetY.animateTo(offsetY.value + 200f, tween(250)) }
```

```dart
_exitScaleController.animateTo(0.1, duration: const Duration(milliseconds: 250));
_alphaController.animateTo(0, duration: const Duration(milliseconds: 250));
_offsetYController.animateTo(_offsetYController.value + 200, ...);
```
✅ 一致

### 按压缩放动画
```kotlin
// Kotlin
val pressScale by animateFloatAsState(
    targetValue = if (isPressed) 0.96f else 1f,
    animationSpec = spring(stiffness = Spring.StiffnessMedium, dampingRatio = 0.6f)
)
```

```dart
// Dart - damping = 2 * sqrt(500) * 0.6 ≈ 26.83
final spring = SpringDescription(mass: 1.0, stiffness: 500.0, damping: 26.83);
```
✅ 一致 (2026-04-09 修复)

## FolderDropRow 参数对比

### 动画参数
| 参数 | Kotlin | Dart | 状态 |
|------|--------|------|------|
| scale (active) | 1.2f | 1.2 | ✅ |
| scale (inactive) | 0.82f | 0.82 | ✅ |
| scale spring | damping=0.6f, stiffness=320f | damping≈21.47, stiffness=320 | ✅ |
| lift (active) | -8dp | -8.0 | ✅ |
| lift (inactive) | 0dp | 0.0 | ✅ |
| itemWidth (active) | 88dp | 88.0 | ✅ |
| itemWidth (inactive) | 68dp | 68.0 | ✅ |

### 显示/隐藏动画
```kotlin
AnimatedVisibility(
    enter = slideInVertically(animationSpec = tween(200)) { it } + fadeIn(animationSpec = tween(200)),
    exit = slideOutVertically(animationSpec = tween(200)) { it } + fadeOut(animationSpec = tween(200)),
)
```
✅ 一致 (EdgeInsets + AnimatedBuilder)

### 碰撞检测参数
| 参数 | Kotlin | Dart | 状态 |
|------|--------|------|------|
| bandPadding | 90f | 90.0 | ✅ |
| stickyRadius | 280f | 280.0 | ✅ |
| horizontalSwipeThreshold | 500f | 500.0 | ✅ |

### 边缘滚动参数
| 参数 | Kotlin | Dart | 状态 |
|------|--------|------|------|
| edgeThreshold | 100f | 100.0 | ✅ |
| minScrollSpeed | 6f | 6.0 | ✅ |
| maxScrollSpeed | 36f | 36.0 | ✅ |

### 特殊行为
- ✅ 进入文件夹模式时重置滚动位置到开头 (2026-04-09 修复)

## 待实现功能

1. **声音反馈**: Kotlin 有 `onDeleteSound`, `onLikeSound`, `onSwipeSound` 回调，Dart 尚未实现
2. **撤销动画 (Undo)**: Kotlin 支持 `undoToken`, `undoDirection` 进行撤销动画，Dart 尚未实现
3. **视频支持**: Kotlin 支持视频播放，Dart 仅支持图片

## 已修复的问题

1. ✅ 触觉反馈类型 (HapticFeedbackType.LongPress -> HapticFeedback.mediumImpact)
2. ✅ 碰撞检测关键逻辑
3. ✅ 桶位置初始化时机
4. ✅ 边缘滚动参数与 Kotlin 一致
5. ✅ 背景卡片堆叠偏移与主卡一致
6. ✅ 进入文件夹模式时重置滚动位置
7. ✅ 文件夹模式未命中目标时正确回弹（不触发滑动）
8. ✅ Action Indicator 文件夹阈值修正为 150f
9. ✅ 按压缩放动画阻尼参数修正 (15.0 → 26.83)
10. ✅ 代码清理：移除未使用的 _folderDropRowThreshold 字段
11. ✅ 堆叠动画：添加 spring 动画实现 (stiffness=350, dampingRatio=0.75)

## 参考来源

- Kotlin 源码: `.claude/skills/photoo/android/app/src/main/com/voicelike/app/NativeVoiceLikeActivity.kt`
- FolderDropTarget: `.claude/skills/photoo/android/app/src/main/com/voicelike/app/FolderDropTarget.kt`
