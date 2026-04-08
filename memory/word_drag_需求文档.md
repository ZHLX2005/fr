---
name: word_drag 需求文档
description: 单词拖拽背单词功能模块交互效果和回调机制
type: reference
---

# WordDrag 模块交互效果文档

## 1. 核心交互效果总览 (photox 实现)

| 滑动方向 | 效果 | 回调 |
|---------|------|------|
| 上滑 | 卡片飞走 → 保留/跳过 | `onSwipeUp()` |
| 左滑 | 卡片飞走 → 删除到垃圾桶 | `onSwipeLeft()` |
| 右滑 | 卡片飞走 → 喜欢 | `onSwipeRight()` |
| **下滑 > 300px** | **显示文件夹选择器** | `FolderDropRow` |
| 未达阈值 | 弹性回弹 | `spring(stiffness=2000f, damping=0.85f)` |

## 2. photoo 核心滑动实现 (NativeVoiceLikeActivity.kt)

### 2.1 DraggableCard 核心参数 (第 4388-4800 行)

```kotlin
// 关键常量
val threshold = 160f           // 滑动确认阈值
val folderModeThreshold = 420f // 下滑进入文件夹模式
val velocityThreshold = 800f   // 快速滑动速度阈值

// 卡片尺寸
.fillMaxWidth(0.8f)
.fillMaxHeight(0.6f)

// 堆叠效果
val scaleValue = 1f - (effectiveStackIndex.coerceAtMost(2) * 0.04f)  // 每层缩小4%
val yOffsetValue = effectiveStackIndex * 15.dp                        // 每层下移15dp

// 旋转角度 (已移除，仅在 LowQualityView 中保留)
val rotation = (offsetX.value / 60).coerceIn(-10f, 10f)

// 下滑时卡片缩小
val dynamicScale = when {
    offsetY.value < 0 -> (1f + offsetY.value / 1000f).coerceAtLeast(0.9f)  // 上滑变薄
    offsetY.value > 0 -> (1f - offsetY.value / 1000f).coerceAtLeast(0.5f)  // 下滑变小
    else -> 1f
}

// 回弹动画 (Snappy)
spring(stiffness = 2000f, dampingRatio = 0.85f)

// 飞出动画
offsetX.animateTo(-1500f, tween(200, easing = FastOutLinearInEasing))  // 左滑
offsetX.animateTo(1500f, tween(200, easing = FastOutLinearInEasing))   // 右滑
offsetY.animateTo(-2000f, tween(200, easing = FastOutLinearInEasing)) // 上滑
```

### 2.2 手势检测 (第 4696-4796 行)

```kotlin
pointerInput(isTopCard, isExpanded, isVideoSeeking) {
    detectDragGestures(
        onDragStart = {
            isPressed = true
            velocityTracker.resetTracking()
            currentOnDragStart?.invoke()
        },
        onDragCancel = {
            // 弹性回弹
            offsetX.animateTo(0f, tween(160, easing = LinearOutSlowInEasing))
            offsetY.animateTo(0f, tween(160, easing = LinearOutSlowInEasing))
        },
        onDragEnd = {
            val velocity = velocityTracker.calculateVelocity()

            // 下滑 > 420px 进入文件夹模式
            val isFolderMode = offsetY.value > 420f

            when {
                // 左滑 - 删除
                !isFolderMode && offsetX.value < -threshold -> {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    offsetX.animateTo(-1500f, tween(200))
                    onSwipeLeft()
                }
                // 右滑 - 喜欢
                !isFolderMode && offsetX.value > threshold -> {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    offsetX.animateTo(1500f, tween(200))
                    onSwipeRight()
                }
                // 上滑 - 跳过
                offsetY.value < -threshold || velocityY < -velocityThreshold -> {
                    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                    offsetY.animateTo(-2000f, tween(200))
                    onSwipeUp()
                }
                // 回弹
                else -> {
                    offsetX.animateTo(0f, spring(stiffness = 2000f, dampingRatio = 0.85f))
                    offsetY.animateTo(0f, spring(stiffness = 2000f, dampingRatio = 0.85f))
                }
            }
        },
        onDrag = { change, dragAmount ->
            offsetX.snapTo(offsetX.value + dragAmount.x)
            offsetY.snapTo(offsetY.value + dragAmount.y)
        }
    )
}
```

## 3. FolderDropRow 下滑桶组件 (FolderDropTarget.kt)

### 3.1 显示条件

```kotlin
val isFolderDropMode = isDragging && topCardOffset.y > 300f

FolderDropRow(
    visible = isFolderDropMode,  // 下滑 > 300px 时显示
    folders = folderDropTargets,
    activeDropTargetId = activeDropTargetId,
    onFolderPositionsChanged = { ... },
    modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp)
)
```

### 3.2 桶动画效果

```kotlin
// 桶激活时的动画
val scale by animateFloatAsState(
    targetValue = if (isActive) 1.2f else 0.82f,
    animationSpec = spring(dampingRatio = 0.6f, stiffness = 320f)
)
val lift by animateDpAsState(
    targetValue = if (isActive) (-8).dp else 0.dp,
    animationSpec = spring(dampingRatio = 0.7f, stiffness = 320f)
)
val itemWidth by animateDpAsState(
    targetValue = if (isActive) 88.dp else 68.dp,
    animationSpec = spring(dampingRatio = 0.7f, stiffness = 320f)
)

// 进入/退出动画
AnimatedVisibility(
    enter = slideInVertically(animationSpec = tween(200)) { it } + fadeIn(animationSpec = tween(200)),
    exit = slideOutVertically(animationSpec = tween(200)) { it } + fadeOut(animationSpec = tween(200))
)
```

### 3.3 碰撞检测 (第 2292-2335 行)

```kotlin
LaunchedEffect(topCardOffset, isFolderDropMode, folderDropTargetRects) {
    if (isFolderDropMode && folderDropTargetRects.isNotEmpty()) {
        val cardCenterX = (screenWidthPx / 2) + topCardOffset.x
        val cardCenterY = (screenHeightPx / 2) + topCardOffset.y

        // 找到最近的桶
        val bestMatch = validRects.entries.minByOrNull { (_, rect) ->
            val dx = cardCenterX - rect.center.x
            val dy = cardCenterY - rect.center.y
            (dx * dx) + (dy * dy)
        }

        // 阈值 280px 半径内"粘附"
        if (dist < 280f || inBand.isNotEmpty()) {
            activeDropTargetId = bestMatch.key
        }
    }
}
```

### 3.4 边缘滚动 (第 2339-2365 行)

```kotlin
LaunchedEffect(isFolderDropMode) {
    while (isActive) {
        // 当卡片靠近边缘时，自动滚动桶列表
        val scrollSpeed = calculateEdgeScrollSpeed(cardCenterX, screenWidthPx, ...)
        if (scrollSpeed != 0f) {
            folderListState.scrollBy(scrollSpeed)
        }
        delay(16) // ~60fps
    }
}
```

## 4. FluidTransitions 动画工具

```kotlin
object FluidTransitions {
    private val SpringBouncy = spring<Float>(stiffness = MediumLow, dampingRatio = 0.75f)

    val SheetEnter = slideInVertically(initialOffsetY = { it }) +
                     fadeIn(tween(300)) +
                     scaleIn(initialScale = 0.92f, SpringBouncy)

    val PopEnter = scaleIn(initialScale = 0.9f, SpringBouncy) +
                   fadeIn(tween(200))
}
```

## 5. 触觉反馈

```kotlin
val haptic = LocalHapticFeedback.current
val hapticsAllowed = LocalHapticsEnabled.current

// 所有滑动确认时触发
if (hapticsAllowed) {
    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
}
```

## 6. 单词背诵适配

将图片替换为单词卡片:
- `MediaItem` → `Word`
- `FolderData` → `CategoryData` (分类桶)
- 删除垃圾桶 → 标记为"稍后复习"
- 右滑喜欢 → 标记为"已掌握"
- 下滑桶 → 选择分类（如：词性、主题、难度）
