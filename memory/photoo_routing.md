# Photoo 功能路由文档

本文档解释 photoo 项目中各个功能对应的源代码文件，方便学习和参考。

---

## 1. 核心滑动卡片系统

### 1.1 DraggableCard 主组件
**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 4388-5120 行

**功能**: 核心可拖拽卡片组件，实现所有滑动交互逻辑

**关键参数**:
```kotlin
DraggableCard(
    item: MediaItem,           // 媒体项
    isTopCard: Boolean,         // 是否顶层卡片
    stackIndex: Int,            // 堆叠索引
    onSwipeLeft: () -> Unit,    // 左滑回调 (删除/垃圾桶)
    onSwipeRight: () -> Unit,   // 右滑回调 (喜欢)
    onSwipeUp: () -> Unit,      // 上滑回调 (保留/跳过)
    onDetail: () -> Unit,       // 详情回调
    suppressActionIndicators: Boolean,  // 是否隐藏 action 指示器
    undoDirection: SwipeDirection?,      // 撤销方向
)
```

**阈值常量** (第 4520 行):
- `threshold = 160f` - 滑动确认阈值
- `folderModeThreshold` - 下滑进入文件夹模式

### 1.2 卡片动画系统
**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 4443-4517 行

**堆叠效果**:
```kotlin
val scaleValue = 1f - (effectiveStackIndex * 0.04f)  // 每层缩小 4%
val yOffsetValue = (effectiveStackIndex * 15).dp      // 每层下移 15dp
```

**动态缩放** (上下滑动时卡片变形):
```kotlin
val dynamicScale = when {
    offsetY.value < 0 -> (1f + offsetY.value / 1000f).coerceAtLeast(0.9f)  // 上滑变薄
    offsetY.value > 0 -> (1f - offsetY.value / 1000f).coerceAtLeast(0.5f)  // 下滑变小
    else -> 1f
}
```

**弹簧回弹动画** (第 4698-4700 行):
```kotlin
offsetX.animateTo(0f, spring(stiffness = 2000f, dampingRatio = 0.85f))
offsetY.animateTo(0f, spring(stiffness = 2000f, dampingRatio = 0.85f))
```

### 1.3 旋转角度
**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 4506 行

```kotlin
val rotation = (offsetX.value / 60).coerceIn(-10f, 10f)
```

---

## 2. Action 指示器 (右上角提示)

**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 5051-5121 行

**显示条件** (第 5055-5119 行):
| 滑动方向 | 阈值 | 指示器 | 颜色 |
|---------|------|--------|------|
| 右滑 | > 100px | LIKE (❤️) | 橙色 `#FF9800` |
| 左滑 | < -100px | DELETE (🗑️) | 红色 `#EF4444` |
| 上滑 | < -100px | KEEP (⬆️) | 蓝色 `#3B82F6` |
| 下滑 | > 150px | MOVE (📁) | 紫色 `#9C27B0` |

---

## 3. 分类桶选择器 (FolderDropRow)

**文件**: `FolderDropTarget.kt`
**位置**: 第 2100-2400 行

### 3.1 显示条件
```kotlin
val isFolderDropMode = isDragging && topCardOffset.y > 300f
```

### 3.2 FolderDropRow 组件
```kotlin
FolderDropRow(
    visible = isFolderDropMode,
    folders = folderDropTargets,
    activeDropTargetId = activeDropTargetId,
    onFolderPositionsChanged = { ... },
    modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 24.dp)
)
```

### 3.3 桶动画效果
```kotlin
val scale by animateFloatAsState(
    targetValue = if (isActive) 1.2f else 0.82f,
    animationSpec = spring(dampingRatio = 0.6f, stiffness = 320f)
)
val lift by animateDpAsState(
    targetValue = if (isActive) (-8).dp else 0.dp,
    animationSpec = spring(dampingRatio = 0.7f, stiffness = 320f)
)
```

### 3.4 碰撞检测
**文件**: `FolderDropTarget.kt`
**位置**: 第 2292-2335 行

```kotlin
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
```

---

## 4. 手势检测系统

**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 4696-4796 行 (detectDragGestures)

### 4.1 拖拽手势处理
```kotlin
pointerInput(isTopCard, isExpanded, isVideoSeeking) {
    detectDragGestures(
        onDragStart = {
            isPressed = true
            velocityTracker.resetTracking()
            currentOnDragStart?.invoke()
        },
        onDragCancel = {
            offsetX.animateTo(0f, tween(160, easing = LinearOutSlowInEasing))
            offsetY.animateTo(0f, tween(160, easing = LinearOutSlowInEasing))
        },
        onDragEnd = {
            val velocity = velocityTracker.calculateVelocity()
            // 方向判断逻辑...
        },
        onDrag = { change, dragAmount ->
            offsetX.snapTo(offsetX.value + dragAmount.x)
            offsetY.snapTo(offsetY.value + dragAmount.y)
        }
    )
}
```

### 4.2 滑动方向判断
```kotlin
when {
    !isFolderMode && offsetX.value < -threshold -> { /* 左滑删除 */ }
    !isFolderMode && offsetX.value > threshold -> { /* 右滑喜欢 */ }
    offsetY.value < -threshold || velocityY < -velocityThreshold -> { /* 上滑跳过 */ }
    else -> { /* 回弹 */ }
}
```

---

## 5. 触觉反馈系统

**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 4473-4474 行 (LocalHapticFeedback)

```kotlin
val haptic = LocalHapticFeedback.current
val hapticsAllowed = LocalHapticsEnabled.current

// 使用
if (hapticsAllowed) {
    haptic.performHapticFeedback(HapticFeedbackType.LongPress)
}
```

---

## 6. 卡片堆叠渲染

**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 2547-2687 行

```kotlin
// 渲染 6 张卡片，但视觉上最多显示 3 张
val visibleItems = displayMedia.take(6).reversed()

visibleItems.forEachIndexed { index, item ->
    val isTopCard = index == visibleItems.lastIndex
    val rawStackIndex = visibleItems.lastIndex - index
    // ...
    DraggableCard(
        isTopCard = isTopCard,
        stackIndex = rawStackIndex,
        // ...
    )
}
```

---

## 7. 撤销动画系统

**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 4547-4567 行

```kotlin
LaunchedEffect(undoToken, isTopCard) {
    if (undoToken == null || undoDirection == null || !isTopCard) return@LaunchedEffect
    // 从屏幕外滑入动画
    offsetX.snapTo(startX)
    offsetY.snapTo(startY)
    alphaAnim.snapTo(0f)
    exitScale.snapTo(0.96f)
    // 弹性动画回到原位
    launch { offsetX.animateTo(0f, tween(260, easing = FastOutSlowInEasing)) }
    launch { offsetY.animateTo(0f, tween(260, easing = FastOutSlowInEasing)) }
    launch { alphaAnim.animateTo(1f, tween(180)) }
    launch { exitScale.animateTo(1f, tween(220, easing = FastOutSlowInEasing)) }
}
```

---

## 8. 媒体项组件 (PhotoCard)

**文件**: `PhotoCard.kt`
**位置**: 第 51-455 行

**功能**: 单个媒体项的展示组件，支持照片、视频、LivePhoto

**支持的媒体类型**:
- `photo` - 普通照片
- `video` - 视频
- `livePhoto` - Live Photo (iOS)

**EXIF 信息展示** (展开详情时):
- 日期时间
- 分辨率
- 文件大小
- 相机型号
- 地理位置 (带反向地理编码)
- ISO
- 快门速度
- 光圈值
- 焦距

---

## 9. FluidTransitions 动画工具

**文件**: `FluidTransitions.kt`

```kotlin
object FluidTransitions {
    val SpringBouncy = spring<Float>(stiffness = MediumLow, dampingRatio = 0.75f)

    val SheetEnter = slideInVertically(initialOffsetY = { it }) +
                     fadeIn(tween(300)) +
                     scaleIn(initialScale = 0.92f, SpringBouncy)

    val PopEnter = scaleIn(initialScale = 0.9f, SpringBouncy) +
                   fadeIn(tween(200))
}
```

---

## 10. 入口动画

**文件**: `NativeVoiceLikeActivity.kt`
**位置**: 第 2571-2584 行

卡片进入时从下方飞入，带有旋转效果：
```kotlin
val entranceTranslationY = if (isInitialLoad) cardEntryOffsets.getOrElse(index) { Animatable(0f) }.value else 0f
val entranceRotation = if (isInitialLoad) cardEntryRotations.getOrElse(index) { Animatable(0f) }.value else 0f

Box(modifier = Modifier.graphicsLayer {
    translationY = entranceTranslationY
    rotationZ = entranceRotation
}) {
    DraggableCard(...)
}
```

---

## 11. 快速索引

| 功能 | 文件 | 关键行号 |
|------|------|---------|
| DraggableCard 主组件 | `NativeVoiceLikeActivity.kt` | 4388-5120 |
| 卡片堆叠渲染 | `NativeVoiceLikeActivity.kt` | 2547-2687 |
| 手势检测 | `NativeVoiceLikeActivity.kt` | 4696-4796 |
| Action 指示器 | `NativeVoiceLikeActivity.kt` | 5051-5121 |
| 入口动画 | `NativeVoiceLikeActivity.kt` | 2571-2584 |
| 撤销动画 | `NativeVoiceLikeActivity.kt` | 4547-4567 |
| FolderDropRow 组件 | `FolderDropTarget.kt` | 2100-2400 |
| 桶碰撞检测 | `FolderDropTarget.kt` | 2292-2335 |
| PhotoCard 组件 | `PhotoCard.kt` | 51-455 |
| 动画工具 | `FluidTransitions.kt` | - |
| 触觉反馈 | `NativeVoiceLikeActivity.kt` | 4473-4474 |

---

## 12. 学习路径建议

### 12.1 卡片滑动系统
1. 阅读 `NativeVoiceLikeActivity.kt` 第 4388-4700 行 - DraggableCard 核心实现
2. 阅读 `NativeVoiceLikeActivity.kt` 第 4696-4796 行 - 手势检测
3. 阅读 `NativeVoiceLikeActivity.kt` 第 5051-5121 行 - Action 指示器

### 12.2 分类桶系统
1. 阅读 `FolderDropTarget.kt` 第 2100-2200 行 - FolderDropRow 组件
2. 阅读 `FolderDropTarget.kt` 第 2292-2350 行 - 碰撞检测逻辑
3. 阅读 `NativeVoiceLikeActivity.kt` 第 2690-2700 行 - FolderDropRow 调用位置

### 12.3 动画系统
1. 阅读 `FluidTransitions.kt` - 通用动画定义
2. 阅读 `NativeVoiceLikeActivity.kt` 第 4443-4517 行 - 卡片动画状态
3. 阅读 `NativeVoiceLikeActivity.kt` 第 4547-4567 行 - 撤销动画
