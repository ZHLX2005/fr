package com.example.flutter_application_1.native.overlay

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
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

    companion object {
        const val CHANNEL_ID = "FloatingWindowChannel"
        const val NOTIFICATION_ID = 1
        const val ACTION_START = "com.example.flutter_application_1.START_FLOATING"
        const val ACTION_STOP = "com.example.flutter_application_1.STOP_FLOATING"
        const val ACTION_CAPTURE = "com.example.flutter_application_1.CAPTURE_SCREEN"

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
            startForeground(NOTIFICATION_ID, createNotification())
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

    private fun startScreenCaptureForFullScreen() {
        if (!screenshot.captureInitialized) {
            handler.post { Toast.makeText(this, "正在请求截图权限...", Toast.LENGTH_SHORT).show() }
            isWaitingForScreenshotPermission = true
            onScreenshotPermissionNeeded?.invoke()
            return
        }

        val bitmap = screenshot.acquireFrame()
        if (bitmap == null) {
            handler.post { Toast.makeText(this, "截图失败：无法获取图像", Toast.LENGTH_SHORT).show() }
            showFloatingWindow()
            return
        }

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
            if (isWaitingForScreenshotPermission) {
                isWaitingForScreenshotPermission = false
                handler.post { startScreenCaptureForRegion() }
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
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
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
            handler.post { Toast.makeText(this, "正在请求截图权限...", Toast.LENGTH_SHORT).show() }
            isWaitingForScreenshotPermission = true
            onScreenshotPermissionNeeded?.invoke()
            return
        }
        val bitmap = screenshot.acquireFrame()
        if (bitmap == null) {
            handler.post { Toast.makeText(this, "截图失败：无法获取图像", Toast.LENGTH_SHORT).show() }
            showFloatingWindow()
            return
        }
        pendingBitmap = bitmap
        cropAndSendBitmap()
    }

    private fun cropAndSendBitmap() {
        val bitmap = pendingBitmap ?: return
        pendingBitmap = null

        try {
            val left = minOf(selectionStartX, selectionEndX)
            val top = minOf(selectionStartY, selectionEndY)
            val right = maxOf(selectionStartX, selectionEndX)
            val bottom = maxOf(selectionStartY, selectionEndY)

            val cropLeft = left.coerceIn(0, bitmap.width)
            val cropTop = top.coerceIn(0, bitmap.height)
            val cropRight = right.coerceIn(cropLeft, bitmap.width)
            val cropBottom = bottom.coerceIn(cropTop, bitmap.height)
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
