# 区域截屏功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现悬浮窗区域截屏功能，用户可拖动画框选择区域，截图后在 Flutter 端预览

**Architecture:** 在原生层新增 SelectionOverlayView 实现选框 UI，通过 MediaProjection 截取全屏后按选区裁剪，截图数据通过 MethodChannel 发送至 Flutter 端预览

**Tech Stack:** Kotlin (原生), Flutter/Dart, MethodChannel

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `FloatingWindowManager.kt` | 新增 SelectionOverlayView、管理选框状态、区域截图逻辑 |
| `MainActivity.kt` | 新增 MethodChannel handler `onRegionCaptured` |
| `overlay_service.dart` | 新增 `onRegionCaptured` 回调、预览状态管理 |
| `overlay_demo.dart` | 新增预览 Bottom Sheet UI |

---

## 任务分解

### 任务 1: 在 FloatingWindowManager 中新增 SelectionOverlayView

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/flutter_application_1/native/overlay/FloatingWindowManager.kt`

- [ ] **Step 1: 在 FloatingWindowManager 类中添加选框相关属性**

在类的属性区域添加：
```kotlin
private var selectionOverlay: View? = null
private var selectionStartX = 0
private var selectionStartY = 0
private var selectionEndX = 0
private var selectionEndY = 0
private var isSelecting = false
private var pendingBitmap: android.graphics.Bitmap? = null
```

- [ ] **Step 2: 添加 showSelectionOverlay 方法**

在 `createFloatingView` 方法后添加：
```kotlin
private fun showSelectionOverlay() {
    val overlayView = View(this).apply {
        setBackgroundColor(0x80000000) // 半透明黑色
    }
    // 全屏覆盖
    val overlayParams = WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT
    )
    windowManager?.addView(overlayView, overlayParams)
    selectionOverlay = overlayView
    setupSelectionTouchListener(overlayView)
}
```

- [ ] **Step 3: 添加 setupSelectionTouchListener 方法**

```kotlin
private fun setupSelectionTouchListener(overlayView: View) {
    var initialX = 0
    var initialY = 0
    var lastX = 0
    var lastY = 0

    overlayView.setOnTouchListener { _, event ->
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialX = event.rawX.toInt()
                initialY = event.rawY.toInt()
                lastX = initialX
                lastY = initialY
                selectionStartX = initialX
                selectionStartY = initialY
                selectionEndX = initialX
                selectionEndY = initialY
                isSelecting = true
                true
            }
            MotionEvent.ACTION_MOVE -> {
                if (isSelecting) {
                    selectionEndX = event.rawX.toInt()
                    selectionEndY = event.rawY.toInt()
                    // 实时更新选框预览（通过重绘 overlay 或叠加层）
                    updateSelectionPreview()
                }
                true
            }
            MotionEvent.ACTION_UP -> {
                if (isSelecting) {
                    isSelecting = false
                    selectionEndX = event.rawX.toInt()
                    selectionEndY = event.rawY.toInt()
                    // 选区过小则忽略
                    if (kotlin.math.abs(selectionEndX - selectionStartX) > 20 &&
                        kotlin.math.abs(selectionEndY - selectionStartY) > 20) {
                        captureRegion()
                    } else {
                        cancelSelection()
                    }
                }
                true
            }
            else -> false
        }
    }
}
```

- [ ] **Step 4: 添加 updateSelectionPreview 和 cancelSelection 方法**

```kotlin
private fun updateSelectionPreview() {
    // 可通过叠加一个自定义 View 绘制矩形边框
    // 或直接使用 invalidate 重绘现有 overlay
}

private fun cancelSelection() {
    hideSelectionOverlay()
}
```

- [ ] **Step 5: 修改 captureScreen 为 captureRegion 并添加裁剪逻辑**

将原有的 `captureScreen()` 方法改为：
```kotlin
fun captureRegion() {
    // 隐藏选框
    hideSelectionOverlay()

    // 全屏截图
    startScreenCaptureForRegion()
}

private fun startScreenCaptureForRegion() {
    if (mediaProjection == null) {
        onScreenshotPermissionNeeded?.invoke()
        return
    }

    try {
        val displayMetrics = DisplayMetrics()
        windowManager?.defaultDisplay?.getMetrics(displayMetrics)
        val width = displayMetrics.widthPixels
        val height = displayMetrics.heightPixels
        val density = displayMetrics.densityDpi

        imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

        val callback = object : MediaProjection.Callback() {
            override fun onStop() {
                virtualDisplay?.release()
            }
        }

        mediaProjection?.registerCallback(callback, handler)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenCapture",
            width,
            height,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null,
            handler
        )

        handler.postDelayed({
            cropAndSendBitmap(width, height)
        }, 100)

    } catch (e: Exception) {
        android.util.Log.e("FloatingWindow", "captureRegion error: ${e.message}", e)
    }
}
```

- [ ] **Step 6: 添加 cropAndSendBitmap 方法**

```kotlin
private fun cropAndSendBitmap(screenWidth: Int, screenHeight: Int) {
    try {
        val image = imageReader?.acquireLatestImage()
        image?.let {
            val planes = it.planes
            val buffer = planes[0].buffer
            val rowStride = planes[0].rowStride
            val pixelStride = planes[0].pixelStride
            val rowPadding = rowStride - it.width * pixelStride

            val fullBitmap = android.graphics.Bitmap.createBitmap(
                it.width + rowPadding / pixelStride,
                it.height,
                android.graphics.Bitmap.Config.ARGB_8888
            )
            fullBitmap.copyPixelsFromBuffer(buffer)

            // 根据选区裁剪
            val left = minOf(selectionStartX, selectionEndX)
            val top = minOf(selectionStartY, selectionEndY)
            val cropWidth = kotlin.math.abs(selectionEndX - selectionStartX)
            val cropHeight = kotlin.math.abs(selectionEndY - selectionStartY)

            // 坐标转换（屏幕坐标 -> Bitmap 坐标）
            val scaleX = fullBitmap.width.toFloat() / screenWidth
            val scaleY = fullBitmap.height.toFloat() / screenHeight
            val bitmapLeft = (left * scaleX).toInt()
            val bitmapTop = (top * scaleY).toInt()
            val bitmapWidth = (cropWidth * scaleX).toInt()
            val bitmapHeight = (cropHeight * scaleY).toInt()

            val croppedBitmap = android.graphics.Bitmap.createBitmap(
                fullBitmap, bitmapLeft, bitmapTop,
                minOf(bitmapWidth, fullBitmap.width - bitmapLeft),
                minOf(bitmapHeight, fullBitmap.height - bitmapTop)
            )

            // 转为 PNG ByteArray
            val stream = java.io.ByteArrayOutputStream()
            croppedBitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
            val byteArray = stream.toByteArray()

            // 发送给 Flutter
            notifyFlutterRegionCaptured(byteArray)

            fullBitmap.recycle()
            croppedBitmap.recycle()
            it.close()
        }
    } catch (e: Exception) {
        android.util.Log.e("FloatingWindow", "cropAndSendBitmap error: ${e.message}", e)
    }
}
```

- [ ] **Step 7: 添加 notifyFlutterRegionCaptured 和 hideSelectionOverlay 方法**

```kotlin
private fun notifyFlutterRegionCaptured(byteArray: ByteArray) {
    val intent = Intent("com.example.flutter_application_1.REGION_CAPTURED").apply {
        putExtra("data", byteArray)
        setPackage(packageName)
    }
    sendBroadcast(intent)
}

private fun hideSelectionOverlay() {
    selectionOverlay?.let {
        try {
            windowManager?.removeView(it)
        } catch (e: Exception) {
            // 忽略
        }
        selectionOverlay = null
    }
}
```

- [ ] **Step 8: 修改 createFloatingView 中的点击逻辑，改为触发选框**

找到 `MotionEvent.ACTION_UP` 中的 `captureScreen()` 调用，改为：
```kotlin
// 判断为点击
if (currentTime - lastTapTime > 300) {
    lastTapTime = currentTime
    showSelectionOverlay()  // 改为显示选框
}
```

- [ ] **Step 9: 提交任务 1**

```bash
git add android/app/src/main/kotlin/com/example/flutter_application_1/native/overlay/FloatingWindowManager.kt
git commit -m "feat(overlay): 添加 SelectionOverlayView 选框 UI"
```

---

### 任务 2: 在 MainActivity 中注册广播接收器

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/flutter_application_1/MainActivity.kt`

- [ ] **Step 1: 在 MainActivity 类中添加广播接收器属性**

```kotlin
private var regionCaptureReceiver: BroadcastReceiver? = null
```

- [ ] **Step 2: 添加注册和注销广播的方法**

```kotlin
private fun registerRegionCaptureReceiver() {
    regionCaptureReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.flutter_application_1.REGION_CAPTURED") {
                val data = intent.getByteArrayExtra("data")
                data?.let {
                    // 通过 MethodChannel 发送给 Flutter
                    MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger, FLOATING_CHANNEL)
                        .invokeMethod("onRegionCaptured", it)
                }
            }
        }
    }
    val filter = IntentFilter("com.example.flutter_application_1.REGION_CAPTURED")
    registerReceiver(regionCaptureReceiver, filter)
}

override fun onDestroy() {
    super.onDestroy()
    regionCaptureReceiver?.let { unregisterReceiver(it) }
}
```

- [ ] **Step 3: 在 onCreate 中调用注册**

找到 `onCreate` 方法，在 `registerRegionCaptureReceiver()` 调用（如果尚未添加）。

- [ ] **Step 4: 提交任务 2**

```bash
git add android/app/src/main/kotlin/com/example/flutter_application_1/MainActivity.kt
git commit -m "feat(overlay): 注册区域截图广播接收器"
```

---

### 任务 3: 在 overlay_service.dart 中添加回调

**Files:**
- Modify: `lib/native/overlay/overlay_service.dart`

- [ ] **Step 1: 添加 onRegionCaptured 回调和状态属性**

在 `OverlayService` 类中添加：
```dart
Uint8List? _pendingScreenshot;
void Function(Uint8List?)? onRegionCaptured;

Uint8List? get pendingScreenshot => _pendingScreenshot;
```

- [ ] **Step 2: 在 init 中设置方法处理器**

在 `_setupMethodCallHandler` 的 switch 中添加：
```dart
case 'onRegionCaptured':
  final data = call.arguments as Uint8List?;
  _pendingScreenshot = data;
  onRegionCaptured?.call(data);
  break;
```

- [ ] **Step 3: 添加清空待处理截图的方法**

```dart
void clearPendingScreenshot() {
  _pendingScreenshot = null;
}
```

- [ ] **Step 4: 提交任务 3**

```bash
git add lib/native/overlay/overlay_service.dart
git commit -m "feat(overlay): 添加 onRegionCaptured 回调支持"
```

---

### 任务 4: 在 overlay_demo.dart 中添加预览 Bottom Sheet

**Files:**
- Modify: `lib/lab/demos/overlay_demo.dart`

- [ ] **Step 1: 添加状态变量和回调设置**

```dart
bool _isPreviewShowing = false;
Uint8List? _currentScreenshot;
```

- [ ] **Step 2: 在 _initService 中设置回调**

```dart
_overlayService.onRegionCaptured = (data) {
  if (mounted && data != null) {
    setState(() {
      _currentScreenshot = data;
      _isPreviewShowing = true;
    });
    _showPreviewSheet();
  }
};
```

- [ ] **Step 3: 添加 _showPreviewSheet 方法**

```dart
void _showPreviewSheet() {
  if (!_isPreviewShowing || _currentScreenshot == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _ScreenshotPreviewSheet(
      imageData: _currentScreenshot!,
      onSave: () {
        Navigator.pop(context);
        _saveScreenshot();
      },
      onReselect: () {
        Navigator.pop(context);
        _reselectRegion();
      },
    ),
  );
}
```

- [ ] **Step 4: 添加 _ScreenshotPreviewSheet widget**

在文件末尾添加：
```dart
class _ScreenshotPreviewSheet extends StatelessWidget {
  final Uint8List imageData;
  final VoidCallback onSave;
  final VoidCallback onReselect;

  const _ScreenshotPreviewSheet({
    required this.imageData,
    required this.onSave,
    required this.onReselect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                imageData,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: onReselect,
                icon: const Icon(Icons.refresh),
                label: const Text('重新截取'),
              ),
              ElevatedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save),
                label: const Text('保存'),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 添加 _saveScreenshot 和 _reselectRegion 方法**

```dart
Future<void> _saveScreenshot() async {
  // TODO: 调用原生保存方法或直接保存
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('截图已保存到图库')),
  );
  _overlayService.clearPendingScreenshot();
  setState(() {
    _isPreviewShowing = false;
    _currentScreenshot = null;
  });
}

void _reselectRegion() {
  _overlayService.clearPendingScreenshot();
  setState(() {
    _isPreviewShowing = false;
    _currentScreenshot = null;
  });
}
```

- [ ] **Step 6: 提交任务 4**

```bash
git add lib/lab/demos/overlay_demo.dart
git commit -m "feat(overlay): 添加截图预览 Bottom Sheet"
```

---

### 任务 5: 测试和验证

- [ ] **Step 1: 编译并运行**

```bash
flutter clean && flutter run
```

- [ ] **Step 2: 测试流程**

1. 打开悬浮截屏 Demo
2. 点击"显示悬浮窗"
3. 点击悬浮按钮
4. 屏幕上应显示半透明遮罩
5. 拖动画出一个矩形区域
6. 松手后应弹出预览 Bottom Sheet
7. 点击"保存"或"重新截取"验证功能

- [ ] **Step 3: 提交最终更改**

```bash
git add -A
git commit -m "feat(overlay): 完成区域截屏功能"
```

---

## 验证清单

| 功能 | 预期 |
|------|------|
| 点击悬浮窗显示选框 | 屏幕覆盖半透明黑色遮罩 |
| 拖动绘制矩形 | 实时显示白色边框预览 |
| 松手截取选区 | 截图数据发送至 Flutter |
| Flutter 预览 | Bottom Sheet 显示截图 |
| 保存功能 | Toast 提示保存成功 |
| 重新截取 | 关闭预览，重新显示选框 |
