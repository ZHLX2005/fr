# 区域截屏功能设计

## 概述

将悬浮窗截屏功能从全屏截屏升级为区域选择截屏，用户可以拖动画框选择任意区域进行截取。

## 流程

1. 点击悬浮窗 → 显示全屏半透明遮罩（透明度 50%）+ 白色选框光标
2. 用户在遮罩上拖动绘制矩形选区（实时白色边框预览）
3. 松手 → 根据选区坐标裁剪图片
4. 截图数据通过 MethodChannel 发送至 Flutter 端
5. Flutter 显示 Bottom Sheet 预览截图
6. 用户选择"保存"（保存至图库）或"重新截取"（关闭预览，重新显示选框）

## 架构

### 原生层 (Kotlin)

| 组件 | 职责 |
|------|------|
| `SelectionOverlayView` | 全屏选框 UI：半透明黑色遮罩 + 白色矩形边框 |
| `FloatingWindowManager` | 管理选框显示、区域截图、坐标计算 |
| MethodChannel 新增 `onRegionCaptured` | 将截图 `ByteArray` (PNG) 发送至 Flutter |

### Flutter 层

| 组件 | 职责 |
|------|------|
| `OverlayDemoPage` | 接收截图数据，显示预览 Bottom Sheet |
| `OverlayService` | 新增 `onRegionCaptured` 回调，保存/重新截取方法 |

## 交互细节

### 选框绘制
- 初始状态：整个屏幕覆盖半透明黑色遮罩
- 绘制中：实时显示白色矩形边框（2dp 宽度）
- 松手后：隐藏遮罩和选框，触发截图

### 选框坐标计算
- 选区起点：用户按下位置（`rawX`, `rawY`）
- 选区终点：用户抬起位置（`rawX`, `rawY`）
- 需要转换为 Bitmap 裁剪坐标（考虑屏幕密度）

### 截图裁剪
```kotlin
val left = min(startX, endX)
val top = min(startY, endY)
val width = abs(endX - startX)
val height = abs(endY - startY)
val croppedBitmap = Bitmap.createBitmap(fullBitmap, left, top, width, height)
```

### MethodChannel 协议

**新增方法**：`onRegionCaptured`
- 参数：`Uint8List` (PNG 格式的截图数据)
- Flutter 端注册回调接收

**Flutter → 原生**：
- `saveScreenshot()` - 保存当前截图到图库
- `reselectRegion()` - 重新显示选框

## 视觉样式

| 元素 | 样式 |
|------|------|
| 遮罩背景 | 半透明黑色，`0x80000000` |
| 选框边框 | 白色，`0xFFFFFFFF`，2dp 宽度 |
| 选框内部 | 保持透明（透过遮罩显示内容） |
| Flutter 预览 | 白色 Bottom Sheet，截图居中显示 |

## 错误处理

| 场景 | 处理 |
|------|------|
| 选区过小（< 10x10 dp） | 视为无效，重新显示选框 |
| 截图失败 | Toast 提示，不保存 |
| 用户取消（按返回键） | 关闭选框，不截图 |

## 依赖项

- 现有 `OverlayService` MethodChannel 保持兼容
- 新增 `onRegionCaptured` 回调
- 无需新增依赖库
