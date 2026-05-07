---
name: android-media-projection-fix
description: Android 14+ MediaProjection 截屏与 Foreground Service 调试修复指南。当遇到悬浮窗截屏闪退、权限重复申请、SecurityException、截图后无结果显示等问题时使用此 skill。涵盖 MediaProjectionManager、startForeground、FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION、ImageReader/VirtualDisplay 等完整调试链路。当用户提到 MediaProjection、截屏权限、前台服务类型、悬浮窗截图、FOREGROUND_SERVICE_MEDIA_PROJECTION 或 Android 14+ 屏幕录制相关问题时触发。
---

# Android 14+ MediaProjection 悬浮窗截屏修复指南

本 skill 总结了调试 Android 14+ MediaProjection 悬浮窗截屏功能的完整经验，包含 7 轮迭代修复中积累的成功模式和错误案例。

## 涉及文件

| 文件 | 职责 |
|------|------|
| `FloatingWindowManager.kt` | 悬浮窗 Service 主类，管理前台服务、截图流程、权限状态 |
| `MainActivity.kt` | 权限回调处理，`onActivityResult` 中衔接权限与截图 |
| `FloatingWindowScreenshot.kt` | ImageReader + VirtualDisplay 截图实现 |
| `AndroidManifest.xml` | 权限声明与 Service foregroundServiceType 配置 |

---

## 关键修复规则

### 1. promoteToForeground 必须在 getMediaProjection 之前

Android 14+ 要求调用 `getMediaProjection()` 时，进程必须已有一个 `FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` 类型的前台服务在运行。

**正确顺序（onActivityResult 中）：**
```
promoteToForeground()     → 先提升前台服务
getMediaProjection()      → 再获取 MediaProjection
setMediaProjection()      → 最后初始化截图
showFloatingWindow()      → 重建悬浮窗
```

**错误顺序会导致：**
```
SecurityException: Media projections require a foreground service
of type ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
```

### 2. 始终使用 3 参数 startForeground，不依赖 SDK_INT 判断

某些厂商（如荣耀 Honor）Android 14 设备的 `Build.VERSION.SDK_INT` 可能不等于 34，但系统仍要求 foreground service type。

**正确做法：**
```kotlin
fun promoteToForeground() {
    try {
        startForeground(NOTIFICATION_ID, createNotification(), 0x00000020)
    } catch (e: Exception) {
        Log.e("Tag", "promoteToForeground failed: ${e.message}", e)
    }
}
```

**错误做法：**
```kotlin
// 不要这样做！某些 Android 14 设备 SDK_INT != 34
if (Build.VERSION.SDK_INT >= 34) {
    startForeground(id, notification, 0x00000020)
} else {
    startForeground(id, notification)  // 缺少 foregroundServiceType
}
```

### 3. 使用硬编码值替代 ServiceInfo 常量

`ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` 可能在某些 compileSdk 版本中不可用。

```kotlin
// 硬编码值 = 1 << 5 = 32 = 0x00000020
startForeground(NOTIFICATION_ID, createNotification(), 0x00000020)
```

### 4. Manifest 必须声明权限和 foregroundServiceType

```xml
<!-- 权限声明 -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />

<!-- Service 声明 -->
<service
    android:name=".native.overlay.FloatingWindowManager"
    android:exported="false"
    android:foregroundServiceType="mediaProjection" />
```

### 5. acquireFrame 需要重试机制

VirtualDisplay 刚创建时可能还未渲染帧，`acquireLatestImage()` 返回 null。

```kotlin
private var captureRetries = 0

// 在 startScreenCaptureForRegion / startScreenCaptureForFullScreen 中：
val bitmap = screenshot.acquireFrame()
if (bitmap == null) {
    if (captureRetries < 5) {
        captureRetries++
        handler.postDelayed({ /* retry */ }, 200)
        return
    }
    captureRetries = 0
    // 最终失败处理
}
captureRetries = 0
```

### 6. setMediaProjection 自动重试需要延迟

权限授予后自动重试截图时，VirtualDisplay 需要时间初始化。

```kotlin
// 正确：延迟 500ms
handler.postDelayed({ startScreenCaptureForRegion() }, 500)

// 错误：立即执行，VirtualDisplay 还没准备好
handler.post { startScreenCaptureForRegion() }
```

### 7. isWaitingForScreenshotPermission 标志必须正确管理

该标志卡在 `true` 会导致 `startScreenCaptureForRegion` 静默返回，无任何提示。

```kotlin
// 在 catch block 中必须重置
catch (e: Exception) {
    manager?.resetScreenshotPermissionWaiting()  // 必须！
}

// 在 setMediaProjection 中重置
if (isWaitingForScreenshotPermission) {
    isWaitingForScreenshotPermission = false
    handler.postDelayed({ startScreenCaptureForRegion() }, 500)
}
```

---

## 错误案例警示

### 错误 1：使用 import ServiceInfo

```kotlin
import android.app.ServiceInfo  // 编译失败！某些 compileSdk 不包含
startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
```

**修复：** 硬编码 `0x00000020`

### 错误 2：showFloatingWindow 的 else if 分支重复请求权限

```kotlin
// 错误：当 hasScreenshotPermission=true 但 captureInitialized=false 时
// 会再次触发权限请求
if (!captureInitialized && !hasScreenshotPermission) {
    // 首次请求
} else if (hasScreenshotPermission && !captureInitialized) {
    // 不要这个分支！权限已授予，不需要再请求
    onScreenshotPermissionNeeded?.invoke()
}
```

**修复：** 删除 else if 分支，仅在 `!captureInitialized && !hasScreenshotPermission` 时请求

### 错误 3：onActivityResult 中 showFloatingWindow 在 setMediaProjection 之前调用

```kotlin
// 错误顺序
manager.showFloatingWindow()  // captureInitialized=false → 触发权限请求
manager.promoteToForeground()
manager.setMediaProjection(mp) // 设置 captureInitialized=true
```

**修复：** 先 setMediaProjection，再 showFloatingWindow（此时 captureInitialized=true，不会重复请求）

### 错误 4：catch block 未重置等待标志

```kotlin
// 错误：缺少 resetScreenshotPermissionWaiting()
catch (e: Exception) {
    floatingChannel?.notifyPermissionGranted()
    // isWaitingForScreenshotPermission 仍为 true
    // 后续 startScreenCaptureForRegion 会静默 return
}
```

---

## 调试排查清单

当悬浮窗截屏功能异常时，按以下顺序排查：

1. **SecurityException?** → 检查 `promoteToForeground` 是否在 `getMediaProjection` 之前，且使用了 3 参数版本
2. **权限重复申请?** → 检查 `showFloatingWindow` 是否有多余的 else if 分支
3. **截图后无结果?** → 检查 `acquireFrame` 返回值，添加 retry 机制和 Log
4. **静默无响应?** → 检查 `isWaitingForScreenshotPermission` 是否卡在 `true`
5. **编译报错?** → 用 `0x00000020` 替代 `ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`

### 关键 Log 标签

在 logcat 中过滤以下标签排查问题：
- `FloatingWindow` — Service 内部状态日志
- `MainActivity` — 权限回调日志
- `System.err` — SecurityException 堆栈
