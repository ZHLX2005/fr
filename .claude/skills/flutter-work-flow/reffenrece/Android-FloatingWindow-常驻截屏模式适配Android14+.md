# Android FloatingWindow 常驻截屏模式适配 Android 14+

## 项目背景

FloatingWindowManager 是安卓悬浮窗服务的核心类，负责：
- 悬浮窗的创建、显示、隐藏
- 截图功能（全局截屏 + 区域选区截屏）
- 与 Flutter 侧通过 MethodChannel 通信

## 关键难点和技术点

### 问题根因

Android 14+ 对 MediaProjection 做了安全收紧：
- **旧方案**：每次截图创建临时 `VirtualDisplay + ImageReader`，截图后立即释放
- **Android 14+ 行为**：`MediaProjectionManager.createScreenCaptureIntent()` 返回的 token 变成**一次性使用**——第一次截图后 token 失效，后续截图黑屏或失败

### 核心矛盾

| 方案 | 思路 | 问题 |
|------|------|------|
| 临时 VirtualDisplay | 每次截图重新创建，截图后立即 release | Android 14+ token 一次性，第二次截图失效 |
| 常驻 VirtualDisplay | 一次创建，整个 Service 生命周期保持存活 | 需要处理屏幕旋转、资源释放、权限撤回 |

---

## NOK Example (问题代码 — 旧临时方案)

```kotlin
// 每次截图创建临时 VirtualDisplay
private fun startScreenCapture() {
    // 创建临时 ImageReader
    imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

    // 创建临时 VirtualDisplay
    virtualDisplay = mediaProjection?.createVirtualDisplay(
        "ScreenCapture",
        width, height, density,
        DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
        imageReader?.surface, null, handler
    )

    // 等待渲染后取帧
    handler.postDelayed({ takePicture() }, 300)
}

private fun takePicture() {
    val image = imageReader?.acquireLatestImage()
    // ... 处理 bitmap
    // 截图完成后立即释放
    releaseTempCaptureResources()
}

// 释放临时资源
private fun releaseTempCaptureResources() {
    virtualDisplay?.release()
    imageReader?.close()
    virtualDisplay = null
    imageReader = null
}
```

**问题**：Android 14+ 上 `MediaProjection.createVirtualDisplay()` 在 token 失效后返回的 VirtualDisplay 无法正常渲染，导致截图黑屏。

---

## OK Example (修复代码 — 常驻模式)

```kotlin
// ========== 常驻截屏资源 ==========
private var captureImageReader: ImageReader? = null   // 常驻 ImageReader
private var captureVirtualDisplay: VirtualDisplay? = null  // 常驻 VirtualDisplay
private var screenWidth: Int = 0
private var screenHeight: Int = 0
private var screenDensity: Int = 0
private var captureInitialized: Boolean = false

/**
 * ★★★ 初始化常驻截屏资源 ★★★
 * MediaProjection + VirtualDisplay + ImageReader 一次性创建，整个生命周期保持存活
 */
private fun initPersistentCapture(mediaProjection: MediaProjection) {
    if (captureInitialized) return

    val displayMetrics = DisplayMetrics()
    windowManager?.defaultDisplay?.getRealMetrics(displayMetrics)
    screenWidth = displayMetrics.widthPixels
    screenHeight = displayMetrics.heightPixels
    screenDensity = displayMetrics.densityDpi

    // ★ 创建常驻 ImageReader（maxImages=2 足够双缓冲）
    captureImageReader = ImageReader.newInstance(
        screenWidth, screenHeight,
        PixelFormat.RGBA_8888, 2
    )

    // ★ 创建常驻 VirtualDisplay，绑定到 ImageReader.surface
    // 只要不 release()，就可以无限次从 ImageReader 取帧
    captureVirtualDisplay = mediaProjection.createVirtualDisplay(
        "ScreenCapturePersistent",
        screenWidth, screenHeight, screenDensity,
        DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
        captureImageReader!!.surface, null, handler
    )

    // ★ 注册权限撤回回调
    mediaProjection.registerCallback(object : MediaProjection.Callback() {
        override fun onStop() {
            releaseAllCaptureResources()
        }
    }, handler)

    captureInitialized = true
}

/**
 * ★★★ 从常驻 ImageReader 取一帧 ★★★
 * 可反复调用，不需要重新授权
 */
private fun acquireFrame(): Bitmap? {
    if (!captureInitialized || captureImageReader == null) return null
    val image = captureImageReader?.acquireLatestImage() ?: return null
    // ... bitmap 处理
    return bitmap
}
```

---

## 修复思路和原理

### 核心洞察

```
Android 14+ MediaProjection token: 一次性使用
  ↓
旧方案: 每次截图创建新的 VirtualDisplay → token 失效后 VirtualDisplay 黑屏
新方案: 一次创建 VirtualDisplay 持续存活 → 持续接收帧，按需取帧
```

### 方案对比

| 方案 | 生命周期 | 截图次数 | Android 14+ 兼容 |
|------|---------|---------|----------------|
| 临时 VirtualDisplay | 单次截图 | 1次 | ❌ 第二次失效 |
| 常驻 VirtualDisplay | Service 生命周期 | 无限次 | ✅ 正常 |

### 关键设计点

1. **`captureInitialized` 标志**：确保常驻资源只初始化一次
2. **`getRealMetrics()` vs `getMetrics()`**：使用 `getRealMetrics()` 获取真实屏幕尺寸，适配挖孔屏/刘海屏
3. **`maxImages=2`**：双缓冲足够，避免内存浪费
4. **截屏前隐藏悬浮窗**：防止悬浮窗自身被截入画面
5. **错误时恢复悬浮窗**：`cropAndSendBitmap()` 出错时必须调用 `showFloatingWindow()`

---

## 更专业的解决方案思考(Brainstorm)

### 方案1: MediaProjection + MediaRecorder 替代 ImageReader
**思路**：用 `MediaRecorder` 持续录屏，将视频流切分成帧
**评价**：
- 优点：获取视频流更稳定
- 缺点：资源消耗大，需要持续写文件/内存缓冲
- **结论**：不推荐，用于截图场景过重

### 方案2: ImageReader + Image 池化复用
**思路**：预创建多个 Image 对象避免频繁 allocate
**评价**：
- 优点：减少 GC 压力
- 缺点：增加复杂度
- **结论**：当前方案 `acquireLatestImage()` 已足够，`maxImages=2` 自动管理缓冲区

### 方案3: 将常驻资源封装为独立 Manager 类
**思路**：提取 `ScreenCaptureManager`，单一职责
```kotlin
class ScreenCaptureManager(
    private val mediaProjection: MediaProjection,
    private val width: Int,
    private val height: Int,
    private val density: Int
) {
    val imageReader: ImageReader
    val virtualDisplay: VirtualDisplay

    fun acquireFrame(): Bitmap?
    fun release()
}
```
**评价**：
- 优点：职责分离，代码更清晰，易测试
- 缺点：引入新文件
- **结论**：中等复杂度，当前 commit 规模下暂不重构，后续可考虑

### 方案4: 使用 `PixelCopy` 替代 ImageReader
**思路**：`PixelCopy` 可以从 Surface 拷贝帧到 Bitmap
**评价**：
- 优点：API 更现代
- 缺点：需要 Surface 源，不适合 VirtualDisplay 场景
- **结论**：不适用

---

## 经验教训

1. **Android 版本兼容性是分层的**：不是所有 API 行为在所有版本一致，需要针对特定版本做适配
2. **常驻资源的生命周期管理**：初始化、释放、权限撤回回调必须配套，否则会造成内存泄漏或崩溃
3. **截屏前隐藏 UI**：悬浮窗自身不能被截入画面，延迟 100ms 确保 UI 完全消失
4. **错误路径必须恢复状态**：任何可能显示/隐藏悬浮窗的路径（成功或失败）都要确保最终状态正确
5. **调试技巧**：`Log.d` 打印关键变量状态（如 `captureInitialized`、`mediaProjection`）

---

## 相关文件

- `android/app/src/main/kotlin/.../native/overlay/FloatingWindowManager.kt` — 核心修改文件
- Commit: `bb33fb9` — fix(overlay): 重构截屏逻辑为常驻模式，支持反复截屏
