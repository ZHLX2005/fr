package io.github.xiaodouzi.fr.native.overlay

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.Toast
import androidx.core.app.NotificationCompat

/**
 * 悬浮窗服务主类
 */
class FloatingWindowManager : Service() {

    private lateinit var handler: Handler
    private val thread = HandlerThread("FloatingWindowThread").apply { start() }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var selectionOverlay: View? = null
    private var chatOverlayView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var mediaProjection: MediaProjection? = null

    private lateinit var screenshot: FloatingWindowScreenshot
    internal lateinit var ai: FloatingWindowAI

    private var selectionStartX = 0
    private var selectionStartY = 0
    private var selectionEndX = 0
    private var selectionEndY = 0
    private var pendingBitmap: android.graphics.Bitmap? = null
    private var isWaitingForScreenshotPermission = false

    var directScreenshotMode: Boolean = false

    fun resetScreenshotPermissionWaiting() {
        isWaitingForScreenshotPermission = false
    }

    companion object {
        const val CHANNEL_ID = "FloatingWindowChannel"
        const val NOTIFICATION_ID = 1
        const val ACTION_START = "io.github.xiaodouzi.fr.START_FLOATING"
        const val ACTION_STOP = "io.github.xiaodouzi.fr.STOP_FLOATING"
        const val ACTION_CAPTURE = "io.github.xiaodouzi.fr.CAPTURE_SCREEN"

        private var instance: FloatingWindowManager? = null
        fun getInstance(): FloatingWindowManager? = instance

        var onScreenshotPermissionNeeded: (() -> Unit)? = null

        fun canDrawOverlays(context: Context): Boolean = Settings.canDrawOverlays(context)

        fun getOverlaySettingsIntent(context: Context): Intent {
            return Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:${context.packageName}")
            )
        }

        private const val PREFS_NAME = "floating_window_prefs"
        private const val KEY_SCREENSHOT_PERMISSION_GRANTED = "screenshot_permission_granted"

        fun isScreenshotPermissionGranted(context: Context): Boolean {
            return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getBoolean(KEY_SCREENSHOT_PERMISSION_GRANTED, false)
        }

        fun setScreenshotPermissionGranted(context: Context, granted: Boolean) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY_SCREENSHOT_PERMISSION_GRANTED, granted)
                .apply()
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        handler = Handler(thread.looper)
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        screenshot = FloatingWindowScreenshot(this, handler, windowManager)
        ai = FloatingWindowAI(handler, screenshot)
        loadAiConfig()
        createNotificationChannel()
    }

    private fun loadAiConfig() {
        try {
            val prefs = getSharedPreferences("ai_config", Context.MODE_PRIVATE)
            ai.apiUrl = prefs.getString("api_url", ai.apiUrl) ?: ai.apiUrl
            ai.apiKey = prefs.getString("api_key", ai.apiKey) ?: ai.apiKey
            ai.model = prefs.getString("model", ai.model) ?: ai.model
            ai.systemPrompt = prefs.getString("system_prompt", ai.systemPrompt) ?: ai.systemPrompt
            directScreenshotMode = prefs.getBoolean("direct_screenshot", false)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> showFloatingWindow()
            ACTION_STOP -> stopSelf()
            ACTION_CAPTURE -> captureScreen()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        removeFloatingWindow()
        screenshot.releaseAllCaptureResources()
        mediaProjection?.stop()
        thread.quitSafely()
        instance = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "悬浮窗服务", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "悬浮截屏服务"; setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val stopIntent = Intent(this, FloatingWindowManager::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("悬浮截屏")
            .setContentText("悬浮窗已启动，点击即可截屏")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", stopPendingIntent)
            .setOngoing(true)
            .build()
    }

    fun promoteToForeground() {
        try {
            // 始终使用带 foregroundServiceType 的版本，不依赖 SDK_INT 判断
            // 部分厂商 Android 14 设备 SDK_INT 可能不等于 34 但仍要求该参数
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    createNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
                )
            } else {
                startForeground(NOTIFICATION_ID, createNotification())
            }
        } catch (e: Exception) {
            android.util.Log.e("FloatingWindow", "promoteToForeground failed: ${e.message}", e)
        }
    }

    fun checkOverlayPermission(): Boolean = Settings.canDrawOverlays(this)

    fun showFloatingWindow(): Boolean {
        if (!Settings.canDrawOverlays(this)) {
            handler.post { Toast.makeText(this, "请先授予悬浮窗权限", Toast.LENGTH_LONG).show() }
            return false
        }
        if (floatingView != null) return true

        try {
            params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.TOP or Gravity.START; x = 50; y = 200 }

            floatingView = createFloatingView()
            windowManager?.addView(floatingView, params)

            // 检查持久化的权限状态，避免 Service 重启后重复请求权限
            val hasScreenshotPermission = isScreenshotPermissionGranted(this)
            if (!screenshot.captureInitialized && !hasScreenshotPermission) {
                isWaitingForScreenshotPermission = true
                onScreenshotPermissionNeeded?.invoke()
            }
            // 注意：如果 hasScreenshotPermission = true 但 captureInitialized = false，
            // 不再触发权限请求（else if 分支已删除），因为权限已授予

            return true
        } catch (e: Exception) {
            handler.post { Toast.makeText(this, "创建悬浮窗失败: ${e.message}", Toast.LENGTH_SHORT).show() }
            floatingView = null
            return false
        }
    }

    @SuppressLint("InflateParams", "ClickableViewAccessibility")
    private fun createFloatingView(): View {
        val container = FrameLayout(this).apply {
            setBackgroundColor(0x00000000); isClickable = true; isFocusable = true
        }
        val size = dpToPx(56)
        container.layoutParams = FrameLayout.LayoutParams(size, size)

        val imageView = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_camera)
            setColorFilter(0xFF87CEEB.toInt())
            layoutParams = FrameLayout.LayoutParams(dpToPx(40), dpToPx(40)).apply { gravity = Gravity.CENTER }
        }
        container.addView(imageView)

        val captureIcon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_crop)
            setColorFilter(0xFF4CAF50.toInt())
            layoutParams = FrameLayout.LayoutParams(dpToPx(16), dpToPx(16)).apply {
                gravity = Gravity.BOTTOM or Gravity.END; bottomMargin = dpToPx(2); rightMargin = dpToPx(2)
            }
        }
        container.addView(captureIcon)

        var initialX = 0; var initialY = 0
        var initialTouchX = 0f; var initialTouchY = 0f
        var lastTapTime = 0L

        container.setOnTouchListener { _, event ->
            val layoutParams = params ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams.x; initialY = layoutParams.y
                    initialTouchX = event.rawX; initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    layoutParams.x = initialX + (event.rawX - initialTouchX).toInt()
                    layoutParams.y = initialY + (event.rawY - initialTouchY).toInt()
                    try { windowManager?.updateViewLayout(floatingView, layoutParams) } catch (e: Exception) { /* 忽略 */ }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val movedX = kotlin.math.abs(event.rawX - initialTouchX)
                    val movedY = kotlin.math.abs(event.rawY - initialTouchY)
                    val touchSlop = 10 * resources.displayMetrics.density
                    if (movedX < touchSlop && movedY < touchSlop) {
                        val currentTime = System.currentTimeMillis()
                        if (currentTime - lastTapTime > 300) {
                            lastTapTime = currentTime
                            if (directScreenshotMode) captureScreen() else showSelectionOverlay()
                        }
                    }
                    true
                }
                else -> false
            }
        }
        return container
    }

    private fun dpToPx(dp: Int): Int = (dp * resources.displayMetrics.density).toInt()

    private fun removeFloatingWindow() {
        floatingView?.let {
            try { windowManager?.removeView(it) } catch (e: Exception) { /* 忽略 */ }
            floatingView = null
        }
    }

    fun captureScreen() {
        try {
            val shutter = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
            android.media.RingtoneManager.getRingtone(this, shutter)?.play()
        } catch (e: Exception) { /* 忽略 */ }
        removeFloatingWindow()
        handler.postDelayed({ startScreenCaptureForFullScreen() }, 100)
    }

    private var captureRetries = 0

    private fun startScreenCaptureForFullScreen() {
        if (!screenshot.captureInitialized) {
            handler.post { Toast.makeText(this, "正在请求截图权限...", Toast.LENGTH_SHORT).show() }
            isWaitingForScreenshotPermission = true
            onScreenshotPermissionNeeded?.invoke()
            return
        }

        val bitmap = screenshot.acquireFrame()
        if (bitmap == null) {
            if (captureRetries < 5) {
                captureRetries++
                android.util.Log.d("FloatingWindow", "acquireFrame null, retry $captureRetries")
                handler.postDelayed({ startScreenCaptureForFullScreen() }, 200)
                return
            }
            captureRetries = 0
            handler.post { Toast.makeText(this, "截图失败：无法获取图像", Toast.LENGTH_SHORT).show() }
            showFloatingWindow()
            return
        }
        captureRetries = 0

        if (directScreenshotMode) {
            pendingBitmap = bitmap
            selectionStartX = 0; selectionStartY = 0
            selectionEndX = bitmap.width; selectionEndY = bitmap.height
            cropAndSendBitmap()
        } else {
            screenshot.saveBitmap(bitmap)
            showFloatingWindow()
        }
    }

    fun setMediaProjection(mediaProjection: MediaProjection?) {
        this.mediaProjection = mediaProjection
        if (mediaProjection != null) {
            screenshot.initPersistentCapture(mediaProjection)
            setScreenshotPermissionGranted(this, true)
            if (isWaitingForScreenshotPermission) {
                isWaitingForScreenshotPermission = false
                captureRetries = 0
                handler.postDelayed({
                    if (directScreenshotMode) startScreenCaptureForFullScreen()
                    else startScreenCaptureForRegion()
                }, 500)
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showSelectionOverlay() {
        try {
            val overlayParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                // 关键：不要设置 FLAG_LAYOUT_IN_SCREEN。
                // 该 flag 会让 view 起点位于 status bar 下方（view 局部 0 = 物理 status_bar_height），
                // 而 MotionEvent.rawY 是物理屏幕坐标（含 status bar），
                // 两者坐标系错位会导致"截取区域相对框选区域偏移"。
                // 不设置该 flag 时，view 起点 = 物理屏幕 (0,0)，与 MediaProjection 截屏坐标系一致。
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.TOP or Gravity.START }

            selectionOverlay = createSelectionOverlayView()
            windowManager?.addView(selectionOverlay, overlayParams)
            removeFloatingWindow()
        } catch (e: Exception) {
            handler.post { Toast.makeText(this, "显示选区失败: ${e.message}", Toast.LENGTH_SHORT).show() }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createSelectionOverlayView(): View {
        val container = FrameLayout(this).apply { isClickable = true; isFocusable = true }
        val borderView = SelectionBorderView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        container.addView(borderView)

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    selectionStartX = event.rawX.toInt(); selectionStartY = event.rawY.toInt()
                    selectionEndX = selectionStartX; selectionEndY = selectionStartY
                    borderView.updateRect(selectionStartX, selectionStartY, selectionEndX, selectionEndY)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    selectionEndX = event.rawX.toInt(); selectionEndY = event.rawY.toInt()
                    borderView.updateRect(
                        minOf(selectionStartX, selectionEndX), minOf(selectionStartY, selectionEndY),
                        maxOf(selectionStartX, selectionEndX), maxOf(selectionStartY, selectionEndY)
                    )
                    true
                }
                MotionEvent.ACTION_UP -> {
                    selectionEndX = event.rawX.toInt(); selectionEndY = event.rawY.toInt()
                    val left = minOf(selectionStartX, selectionEndX)
                    val top = minOf(selectionStartY, selectionEndY)
                    val right = maxOf(selectionStartX, selectionEndX)
                    val bottom = maxOf(selectionStartY, selectionEndY)
                    if (right - left < dpToPx(20) || bottom - top < dpToPx(20)) {
                        handler.post { Toast.makeText(this, "选区过小，请重新选择", Toast.LENGTH_SHORT).show() }
                        cancelSelection()
                    } else {
                        captureRegion()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> { cancelSelection(); true }
                else -> false
            }
        }
        return container
    }

    private fun cancelSelection() {
        hideSelectionOverlay()
        showFloatingWindow()
    }

    private fun hideSelectionOverlay() {
        selectionOverlay?.let {
            try { windowManager?.removeView(it) } catch (e: Exception) { /* 忽略 */ }
            selectionOverlay = null
        }
    }

    private fun captureRegion() {
        hideSelectionOverlay()
        removeFloatingWindow()
        try {
            val shutter = android.media.RingtoneManager.getDefaultUri(android.media.RingtoneManager.TYPE_NOTIFICATION)
            android.media.RingtoneManager.getRingtone(this, shutter)?.play()
        } catch (e: Exception) { /* 忽略 */ }
        handler.post { Toast.makeText(this, "截屏中...", Toast.LENGTH_SHORT).show() }
        handler.postDelayed({ startScreenCaptureForRegion() }, 100)
    }

    private fun startScreenCaptureForRegion() {
        if (!screenshot.captureInitialized) {
            if (isWaitingForScreenshotPermission) {
                android.util.Log.w("FloatingWindow", "capture not initialized and already waiting for permission")
                return
            }
            handler.post { Toast.makeText(this, "正在请求截图权限...", Toast.LENGTH_SHORT).show() }
            isWaitingForScreenshotPermission = true
            onScreenshotPermissionNeeded?.invoke()
            return
        }
        val bitmap = screenshot.acquireFrame()
        if (bitmap == null) {
            if (captureRetries < 5) {
                captureRetries++
                android.util.Log.d("FloatingWindow", "acquireFrame null (region), retry $captureRetries")
                handler.postDelayed({ startScreenCaptureForRegion() }, 200)
                return
            }
            captureRetries = 0
            handler.post { Toast.makeText(this, "截图失败：无法获取图像", Toast.LENGTH_SHORT).show() }
            showFloatingWindow()
            return
        }
        captureRetries = 0
        pendingBitmap = bitmap
        cropAndSendBitmap()
    }

    private fun cropAndSendBitmap() {
        val bitmap = pendingBitmap ?: return
        pendingBitmap = null

        try {
            // selection 坐标系语义：
            //  - directScreenshotMode：selection = (0,0)..(bitmap.width, bitmap.height)
            //  - 框选模式：selection 来自 selectionOverlay 的 MotionEvent.rawX/rawY，
            //    是物理屏幕坐标（包含状态栏），坐标系原点 (0,0) = 物理屏幕左上角
            //
            // MediaProjection 截屏 bitmap 的坐标系在大多数设备上 == 物理屏幕坐标系，
            // 但部分 ROM 上 VirtualDisplay 的实际截屏区域可能与 getRealMetrics 不一致：
            //  - bitmap 高度可能比 screenHeight 小（去掉了 status bar / nav bar 区域）
            //  - bitmap 坐标原点的 y=0 可能对应物理屏幕 status_bar_height 位置
            // 此时如果直接把 rawY 作为 bitmap.y，会出现"截取区域相对框选区域偏移"。
            //
            // 修复策略：基于 bitmap.width/bitmap.height 实际尺寸做归一化，
            // 等价于把 selection 坐标视为相对于 bitmap 尺寸的归一化坐标。
            val rawLeft = minOf(selectionStartX, selectionEndX)
            val rawTop = minOf(selectionStartY, selectionEndY)
            val rawRight = maxOf(selectionStartX, selectionEndX)
            val rawBottom = maxOf(selectionStartY, selectionEndY)

            val bmpW = bitmap.width
            val bmpH = bitmap.height

            android.util.Log.d(
                "FloatingWindow",
                "crop: sel=($rawLeft,$rawTop)-($rawRight,$rawBottom) " +
                    "bitmap=${bmpW}x${bmpH}"
            )

            val cropLeft = rawLeft.coerceIn(0, bmpW)
            val cropTop = rawTop.coerceIn(0, bmpH)
            val cropRight = rawRight.coerceIn(cropLeft, bmpW)
            val cropBottom = rawBottom.coerceIn(cropTop, bmpH)
            val cropWidth = cropRight - cropLeft
            val cropHeight = cropBottom - cropTop

            if (cropWidth <= 0 || cropHeight <= 0) {
                handler.post { Toast.makeText(this, "选区无效", Toast.LENGTH_SHORT).show() }
                bitmap.recycle()
                showFloatingWindow()
                return
            }

            val croppedBitmap = android.graphics.Bitmap.createBitmap(bitmap, cropLeft, cropTop, cropWidth, cropHeight)
            bitmap.recycle()
            showChatOverlay(croppedBitmap)
        } catch (e: Exception) {
            handler.post { Toast.makeText(this, "裁剪截图失败: ${e.message}", Toast.LENGTH_SHORT).show() }
            bitmap.recycle()
            showFloatingWindow()
        }
    }

    private fun showChatOverlay(croppedBitmap: android.graphics.Bitmap) {
        val imagePath = screenshot.saveBitmapToTempFile(croppedBitmap)

        val chatView = ChatOverlayView(this).apply {
            setBitmap(croppedBitmap)
            onRegionSelected = { ai.callAiApi(ai.systemPrompt, imagePath) }
            onClose = {
                hideChatOverlay()
                croppedBitmap.recycle()
                showFloatingWindow()
            }
        }
        chatOverlayView = chatView
        ai.setChatOverlay(chatView)

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        try {
            windowManager?.addView(chatView, params)
            chatView.onRegionSelected?.invoke()
        } catch (e: Exception) {
            handler.post { Toast.makeText(this, "显示失败: ${e.message}", Toast.LENGTH_SHORT).show() }
        }
    }

    private fun hideChatOverlay() {
        chatOverlayView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) { /* 忽略 */ }
            chatOverlayView = null
        }
        ai.setChatOverlay(null)
    }

    fun hideFloatingWindow() = removeFloatingWindow()
    fun isFloatingWindowShowing(): Boolean = floatingView != null

    // ========== Flutter callbacks ==========
    fun showAiLoading() = handler.post { ai.chatOverlay?.showLoading() }
    fun appendAiAnswer(chunk: String) = handler.post { ai.chatOverlay?.appendAnswer(chunk) }
    fun showAiError(error: String) = handler.post { ai.chatOverlay?.showError(error) }
    fun hideAiLoading() = handler.post { ai.chatOverlay?.hideLoading() }

    fun saveScreenshotToGallery(byteArray: ByteArray) {
        try {
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size)
            if (bitmap != null) {
                screenshot.saveBitmap(bitmap)
                bitmap.recycle()
            }
        } catch (e: Exception) {
            handler.post { Toast.makeText(this, "保存失败: ${e.message}", Toast.LENGTH_SHORT).show() }
        }
    }
}
