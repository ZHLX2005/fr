---
name: Gb01-MediaProjection前台服务
description: Android 14+ MediaProjection 截屏与 Foreground Service 调试修复指南。当遇到悬浮窗截屏闪退、权限重复申请、SecurityException、IllegalArgumentException、Unable to start service、截图后无结果显示、设备运行旧 APK 等问题时使用此 skill。涵盖 MediaProjectionManager、startForeground、FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION、ImageReader/VirtualDisplay 等完整调试链路；按异常类型分类的排查 SOP 见 references/Gb02-FGS异常排查案例.md。当用户提到 MediaProjection、截屏权限、前台服务类型、悬浮窗截图、FOREGROUND_SERVICE_MEDIA_PROJECTION、Foreground Service type 不匹配、Android 14+ 屏幕录制、SecurityException around startForeground、PigmentFloatingManager、悬浮窗 FGS 异常，或任何 Android 14+/15 foreground service 与 MediaProjection 相关问题（含设备运行 APK 与源码不一致）时触发。
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

### 2. promoteToForeground：ServiceInfo 常量 + SDK_INT >= Q 分支调 3 参 startForeground

**现行做法（与现网 FloatingWindowManager.kt / PigmentFloatingManager.kt 一致）：**

```kotlin
fun promoteToForeground() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        startForeground(
            NOTIFICATION_ID,
            createNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
        )
    } else {
        startForeground(NOTIFICATION_ID, createNotification())
    }
}
```

3 参重载是 API 29 才存在的 API；本项目 minSdk 24，**无条件调 3 参会在 API 24-28 直接 `NoSuchMethodError`**，所以必须 `SDK_INT >= Q` 分支 + 2 参兜底。pre-Q 上 manifest 也没有 `foregroundServiceType` 属性，2 参即可。

> **历史记录（已废弃）**：早期一轮修复曾在部分厂商（如荣耀 Honor）Android 14 设备上观察到 `SDK_INT != 34` 仍要求 foreground service type，当时把结论写成「无条件 3 参 + 硬编码 `0x00000020`」。该做法在 API 24-28 必崩；且 `0x00000020` 与 `ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` 是同一个值，硬编码没有任何收益——已废弃，不要照搬。

### 3. 类型常量直接用 `ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`，不要硬编码

`ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION`（= 1 << 5 = 0x20）在本仓库 compileSdk 下编译正常——现网两个 Service 均 `import android.content.pm.ServiceInfo` 后直接用常量，编译发布无问题。

> **历史记录（已废弃）**：旧结论「ServiceInfo 常量可能编译失败、须硬编码 `0x00000020`」源于一次本地 compileSdk/gradle 配置问题，不代表现状。如今写硬编码反而会被 FGS 排查 SOP 当作 stale bitmask 嫌疑（见 [[Gb02-FGS异常排查案例]] Rule 1）。再遇「常量编译失败」，先查 compileSdk 配置，不要回退硬编码。

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

### 错误 1：使用 import ServiceInfo ——（历史记录，已废弃）

> 早期某次本地构建曾报 `ServiceInfo` 常量不可用，当时的 workaround 是硬编码 `0x00000020`：
>
> ```kotlin
> import android.app.ServiceInfo  // 当时编译失败
> startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
> ```
>
> **该结论已废弃**：现网 FloatingWindowManager.kt / PigmentFloatingManager.kt 都直接 `import android.content.pm.ServiceInfo` + 常量，编译发布正常。若再遇「常量编译失败」，是本地 compileSdk/gradle 配置问题，修配置，不要回退硬编码。

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

1. **SecurityException?** → 检查 `promoteToForeground` 是否在 `getMediaProjection` 之前，且按 `SDK_INT >= Q` 分支用了带 type 的 3 参版本
2. **权限重复申请?** → 检查 `showFloatingWindow` 是否有多余的 else if 分支
3. **截图后无结果?** → 检查 `acquireFrame` 返回值，添加 retry 机制和 Log
4. **静默无响应?** → 检查 `isWaitingForScreenshotPermission` 是否卡在 `true`
5. **编译报错?** → 先查 compileSdk/gradle 配置；不要用 `0x00000020` 硬编码替代 `ServiceInfo` 常量（历史 workaround 已废弃，见规则 3）

### 关键 Log 标签

在 logcat 中过滤以下标签排查问题：
- `FloatingWindow` — Service 内部状态日志
- `MainActivity` — 权限回调日志
- `System.err` — SecurityException 堆栈

---

## 何时读哪个 ref

主文档承担 **7 轮修复经验的主线**（promoteToForeground 顺序、ServiceInfo 常量 + SDK_INT 分支、retry 机制等）。以下特化场景需加载 ref：

| ref | 何时读取 | 路径 |
|---|---|---|
| [[Gb02-FGS异常排查案例]] | 按异常类型排查 subset mismatch、权限时机或 APK/源码不一致问题 | [[Gb02-FGS异常排查案例]] |
