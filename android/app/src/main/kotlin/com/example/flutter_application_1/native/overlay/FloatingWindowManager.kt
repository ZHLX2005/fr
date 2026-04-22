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
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.net.Uri
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.util.Base64
import java.io.BufferedReader
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.io.OutputStreamWriter

/**
 * 悬浮窗管理器 - 统一管理原生悬浮窗功能
 * 包含权限检查、悬浮窗显示、截图等功能
 */
class FloatingWindowManager : Service() {

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var selectionOverlay: View? = null
    private var chatOverlay: ChatOverlayView? = null
    private var params: WindowManager.LayoutParams? = null
    private var mediaProjection: MediaProjection? = null
    private lateinit var handler: Handler
    private val thread = HandlerThread("FloatingWindowThread").apply { start() }

    // ========== 常驻截屏资源（方案 B：保持 MediaProjection 存活，按需取帧）==========
    private var captureImageReader: ImageReader? = null
    private var captureVirtualDisplay: VirtualDisplay? = null
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var screenDensity: Int = 0
    private var captureInitialized: Boolean = false
    // ========== END 常驻截屏资源 ==========

    // Selection overlay properties
    private var selectionStartX = 0
    private var selectionStartY = 0
    private var selectionEndX = 0
    private var selectionEndY = 0
    private var pendingBitmap: android.graphics.Bitmap? = null
    private var pendingCroppedBitmap: android.graphics.Bitmap? = null
    private var isWaitingForScreenshotPermission = false

    // AI 配置
    var apiUrl: String = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    var apiKey: String = ""
    var model: String = "glm-4v-flash"
    var systemPrompt: String = "你是一个专业的AI助手，请根据图片回答用户问题。"
    var directScreenshotMode: Boolean = false

    companion object {
        const val CHANNEL_ID = "FloatingWindowChannel"
        const val NOTIFICATION_ID = 1
        const val ACTION_START = "com.example.flutter_application_1.START_FLOATING"
        const val ACTION_STOP = "com.example.flutter_application_1.STOP_FLOATING"
        const val ACTION_CAPTURE = "com.example.flutter_application_1.CAPTURE_SCREEN"

        private var instance: FloatingWindowManager? = null

        fun getInstance(): FloatingWindowManager? = instance

        // 截图权限请求回调
        var onScreenshotPermissionNeeded: (() -> Unit)? = null

        /**
         * 检查是否有悬浮窗权限
         */
        fun canDrawOverlays(context: Context): Boolean {
            return Settings.canDrawOverlays(context)
        }

        /**
         * 获取跳转至悬浮窗权限设置页的Intent
         */
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
        createNotificationChannel()
        handler = Handler(thread.looper)
        loadAiConfig()
    }

    private fun loadAiConfig() {
        try {
            val prefs = getApplicationContext().getSharedPreferences("ai_config", Context.MODE_PRIVATE)
            apiUrl = prefs.getString("api_url", apiUrl) ?: apiUrl
            apiKey = prefs.getString("api_key", apiKey) ?: apiKey
            model = prefs.getString("model", model) ?: model
            systemPrompt = prefs.getString("system_prompt", systemPrompt) ?: systemPrompt
            directScreenshotMode = prefs.getBoolean("direct_screenshot", false)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                showFloatingWindow()
            }
            ACTION_STOP -> {
                stopSelf()
            }
            ACTION_CAPTURE -> {
                captureScreen()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        removeFloatingWindow()
        releaseMediaProjection()
        thread.quitSafely()
        instance = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "悬浮窗服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "悬浮截屏服务"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val stopIntent = Intent(this, FloatingWindowManager::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
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

    fun checkOverlayPermission(): Boolean {
        return Settings.canDrawOverlays(this)
    }

    fun promoteToForeground() {
        try {
            startForeground(NOTIFICATION_ID, createNotification())
            android.util.Log.d("FloatingWindow", "promoteToForeground: success")
        } catch (e: Exception) {
            android.util.Log.e("FloatingWindow", "promoteToForeground failed: ${e.message}", e)
        }
    }

    fun showFloatingWindow(): Boolean {
        if (!Settings.canDrawOverlays(this)) {
            handler.post {
                Toast.makeText(this, "请先授予悬浮窗权限", Toast.LENGTH_LONG).show()
            }
            return false
        }

        if (floatingView != null) {
            return true
        }

        try {
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

            val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN

            params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                flags,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 50
                y = 200
            }

            floatingView = createFloatingView(applicationContext)
            windowManager?.addView(floatingView, params)
            return true

        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "创建悬浮窗失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
            floatingView = null
            return false
        }
    }

    @SuppressLint("InflateParams", "ClickableViewAccessibility")
    private fun createFloatingView(context: Context): View {
        val container = FrameLayout(context).apply {
            setBackgroundColor(0x00000000)
            isClickable = true
            isFocusable = true
        }

        val size = dpToPx(56)
        container.layoutParams = FrameLayout.LayoutParams(size, size)

        val imageView = ImageView(context).apply {
            setImageResource(android.R.drawable.ic_menu_camera)
            setColorFilter(0xFF87CEEB.toInt())
            layoutParams = FrameLayout.LayoutParams(dpToPx(40), dpToPx(40)).apply {
                gravity = Gravity.CENTER
            }
        }
        container.addView(imageView)

        val captureIcon = ImageView(context).apply {
            setImageResource(android.R.drawable.ic_menu_crop)
            setColorFilter(0xFF4CAF50.toInt())
            layoutParams = FrameLayout.LayoutParams(dpToPx(16), dpToPx(16)).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                bottomMargin = dpToPx(2)
                rightMargin = dpToPx(2)
            }
        }
        container.addView(captureIcon)

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var lastTapTime = 0L

        container.setOnTouchListener { _, event ->
            val layoutParams = params ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams.x
                    initialY = layoutParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    layoutParams.x = initialX + (event.rawX - initialTouchX).toInt()
                    layoutParams.y = initialY + (event.rawY - initialTouchY).toInt()
                    try {
                        windowManager?.updateViewLayout(floatingView, layoutParams)
                    } catch (e: Exception) {
                        // 忽略
                    }
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
                            if (directScreenshotMode) {
                                captureScreen()
                            } else {
                                showSelectionOverlay()
                            }
                        }
                    }
                    true
                }
                else -> false
            }
        }

        return container
    }

    private fun dpToPx(dp: Int): Int {
        val density = resources.displayMetrics.density
        return (dp * density).toInt()
    }

    private fun removeFloatingWindow() {
        floatingView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            floatingView = null
        }
    }

    fun captureScreen() {
        try {
            val shutter = android.media.RingtoneManager.getDefaultUri(
                android.media.RingtoneManager.TYPE_NOTIFICATION
            )
            val ringtone = android.media.RingtoneManager.getRingtone(this, shutter)
            ringtone?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }

        removeFloatingWindow()
        handler.postDelayed({
            startScreenCaptureForFullScreen()
        }, 100)
    }

    private fun startScreenCaptureForFullScreen() {
        android.util.Log.d("FloatingWindow", ">>> startScreenCaptureForFullScreen, captureInitialized=$captureInitialized, directScreenshotMode=$directScreenshotMode")

        if (!captureInitialized) {
            handler.post {
                Toast.makeText(this, "正在请求截图权限...", Toast.LENGTH_SHORT).show()
            }
            onScreenshotPermissionNeeded?.invoke()
            return
        }

        val bitmap = acquireFrame()
        if (bitmap == null) {
            handler.post {
                Toast.makeText(this, "截图失败：无法获取图像", Toast.LENGTH_SHORT).show()
            }
            showFloatingWindow()
            return
        }

        if (directScreenshotMode) {
            pendingBitmap = bitmap
            selectionStartX = 0
            selectionStartY = 0
            selectionEndX = bitmap.width
            selectionEndY = bitmap.height
            cropAndSendBitmap(bitmap.width, bitmap.height)
        } else {
            saveBitmap(bitmap)
            showFloatingWindow()
        }
    }

    private fun saveBitmap(bitmap: android.graphics.Bitmap) {
        try {
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val filename = "screenshot_$timestamp.png"
            android.util.Log.d("FloatingWindow", "saveBitmap: filename=$filename SDK=${Build.VERSION.SDK_INT}")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                android.util.Log.d("FloatingWindow", "saveBitmap: using MediaStore API (Android 10+)")
                val contentValues = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, filename)
                    put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Screenshots")
                    put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                }

                android.util.Log.d("FloatingWindow", "saveBitmap: inserting into MediaStore")
                val uri = contentResolver.insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, contentValues)
                android.util.Log.d("FloatingWindow", "saveBitmap: uri=$uri")
                uri?.let {
                    android.util.Log.d("FloatingWindow", "saveBitmap: opening output stream")
                    contentResolver.openOutputStream(it)?.use { outputStream ->
                        val compressed = bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, outputStream)
                        android.util.Log.d("FloatingWindow", "saveBitmap: compress result=$compressed")
                    }

                    contentValues.clear()
                    contentValues.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                    val updated = contentResolver.update(it, contentValues, null, null)
                    android.util.Log.d("FloatingWindow", "saveBitmap: IS_PENDING cleared, update result=$updated")

                    handler.post {
                        try {
                            Toast.makeText(this, "截图已保存到图库", Toast.LENGTH_LONG).show()
                        } catch (e: Exception) {
                            // 忽略
                        }
                    }

                    notifyFlutterScreenshot(it.toString())
                    android.util.Log.d("FloatingWindow", "saveBitmap: success for Android 10+")
                    return
                }
                android.util.Log.e("FloatingWindow", "saveBitmap: uri is null, MediaStore insert failed")
            }

            // Android 9 及以下
            android.util.Log.d("FloatingWindow", "saveBitmap: using legacy file API")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Screenshots")
            if (!dir.exists()) {
                val created = dir.mkdirs()
                android.util.Log.d("FloatingWindow", "saveBitmap: created dir=$created")
            }

            val file = File(dir, filename)
            android.util.Log.d("FloatingWindow", "saveBitmap: file=${file.absolutePath}")
            FileOutputStream(file).use { out ->
                val compressed = bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
                android.util.Log.d("FloatingWindow", "saveBitmap: compress result=$compressed")
            }

            val intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            intent.data = Uri.fromFile(file)
            sendBroadcast(intent)

            handler.post {
                try {
                    Toast.makeText(this, "截图已保存到图库", Toast.LENGTH_LONG).show()
                } catch (e: Exception) {
                    // 忽略
                }
            }

            notifyFlutterScreenshot(file.absolutePath)
            android.util.Log.d("FloatingWindow", "saveBitmap: success for legacy API")

        } catch (e: Exception) {
            android.util.Log.e("FloatingWindow", "saveBitmap error: ${e.message}", e)
            e.printStackTrace()
            handler.post {
                try {
                    Toast.makeText(this, "保存截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
                } catch (e2: Exception) {
                    // 忽略
                }
            }
        }
    }

    private fun notifyFlutterScreenshot(path: String) {
        try {
            val intent = Intent("com.example.flutter_application_1.SCREENSHOT_COMPLETED").apply {
                putExtra("path", path)
                setPackage(packageName)
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            // 忽略
        }
    }

    fun setMediaProjection(mediaProjection: MediaProjection?) {
        this.mediaProjection = mediaProjection

        if (mediaProjection != null) {
            initPersistentCapture(mediaProjection)

            if (isWaitingForScreenshotPermission) {
                android.util.Log.d("FloatingWindow", "setMediaProjection: permission granted, continuing screenshot")
                isWaitingForScreenshotPermission = false
                handler.post {
                    startScreenCaptureForRegion()
                }
            }
        }
    }

    @SuppressLint("WrongConstant")
    private fun initPersistentCapture(mediaProjection: MediaProjection) {
        if (captureInitialized) {
            android.util.Log.d("FloatingWindow", "initPersistentCapture: already initialized, skip")
            return
        }

        val displayMetrics = DisplayMetrics()
        windowManager?.defaultDisplay?.getRealMetrics(displayMetrics)
        screenWidth = displayMetrics.widthPixels
        screenHeight = displayMetrics.heightPixels
        screenDensity = displayMetrics.densityDpi

        android.util.Log.d("FloatingWindow", "initPersistentCapture: ${screenWidth}x${screenHeight} density=$screenDensity")

        mediaProjection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                android.util.Log.d("FloatingWindow", "initPersistentCapture: MediaProjection onStop")
                releaseAllCaptureResources()
                handler.post {
                    Toast.makeText(this@FloatingWindowManager, "截屏权限已取消", Toast.LENGTH_SHORT).show()
                }
            }
        }, handler)

        captureImageReader = ImageReader.newInstance(
            screenWidth, screenHeight,
            PixelFormat.RGBA_8888,
            2
        )

        captureVirtualDisplay = mediaProjection.createVirtualDisplay(
            "ScreenCapturePersistent",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            captureImageReader!!.surface,
            null, handler
        )

        captureInitialized = true
        android.util.Log.d("FloatingWindow", "initPersistentCapture: success")
    }

    private fun acquireFrame(): android.graphics.Bitmap? {
        if (!captureInitialized || captureImageReader == null) {
            android.util.Log.e("FloatingWindow", "acquireFrame: capture not initialized")
            return null
        }

        val image = captureImageReader?.acquireLatestImage()
        if (image == null) {
            android.util.Log.e("FloatingWindow", "acquireFrame: image is null")
            return null
        }

        try {
            val planes = image.planes
            val buffer = planes[0].buffer
            val rowStride = planes[0].rowStride
            val pixelStride = planes[0].pixelStride
            val rowPadding = rowStride - image.width * pixelStride

            val bitmap = android.graphics.Bitmap.createBitmap(
                image.width + rowPadding / pixelStride,
                image.height,
                android.graphics.Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)

            val cropped = android.graphics.Bitmap.createBitmap(
                bitmap, 0, 0,
                image.width.coerceAtMost(screenWidth),
                image.height.coerceAtMost(screenHeight)
            )

            if (cropped != bitmap) bitmap.recycle()
            image.close()

            return cropped
        } catch (e: Exception) {
            android.util.Log.e("FloatingWindow", "acquireFrame error: ${e.message}", e)
            image.close()
            return null
        }
    }

    private fun releaseMediaProjection() {
        releaseAllCaptureResources()
        try {
            mediaProjection?.stop()
        } catch (e: Exception) {
            // 忽略
        }
        mediaProjection = null
    }

    private fun releaseAllCaptureResources() {
        try {
            captureVirtualDisplay?.release()
        } catch (e: Exception) {
            // 忽略
        }
        try {
            captureImageReader?.close()
        } catch (e: Exception) {
            // 忽略
        }
        captureVirtualDisplay = null
        captureImageReader = null
        captureInitialized = false
    }

    fun hideFloatingWindow() {
        removeFloatingWindow()
    }

    fun isFloatingWindowShowing(): Boolean {
        return floatingView != null
    }

    @SuppressLint("InflateParams", "ClickableViewAccessibility")
    private fun showSelectionOverlay() {
        try {
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

            val flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_FULLSCREEN

            val overlayParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                flags,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.TOP or Gravity.START
            }

            selectionOverlay = createSelectionOverlayView(applicationContext)
            windowManager?.addView(selectionOverlay, overlayParams)
            removeFloatingWindow()

        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "显示选区失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    @SuppressLint("InflateParams", "ClickableViewAccessibility")
    private fun createSelectionOverlayView(context: Context): View {
        val container = FrameLayout(context).apply {
            isClickable = true
            isFocusable = true
        }

        val borderView = SelectionBorderView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        container.addView(borderView)

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    selectionStartX = event.rawX.toInt()
                    selectionStartY = event.rawY.toInt()
                    selectionEndX = selectionStartX
                    selectionEndY = selectionStartY
                    borderView.updateRect(selectionStartX, selectionStartY, selectionEndX, selectionEndY)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    selectionEndX = event.rawX.toInt()
                    selectionEndY = event.rawY.toInt()
                    borderView.updateRect(
                        minOf(selectionStartX, selectionEndX),
                        minOf(selectionStartY, selectionEndY),
                        maxOf(selectionStartX, selectionEndX),
                        maxOf(selectionStartY, selectionEndY)
                    )
                    true
                }
                MotionEvent.ACTION_UP -> {
                    selectionEndX = event.rawX.toInt()
                    selectionEndY = event.rawY.toInt()

                    val left = minOf(selectionStartX, selectionEndX)
                    val top = minOf(selectionStartY, selectionEndY)
                    val right = maxOf(selectionStartX, selectionEndX)
                    val bottom = maxOf(selectionStartY, selectionEndY)
                    val width = right - left
                    val height = bottom - top

                    if (width < dpToPx(20) || height < dpToPx(20)) {
                        handler.post {
                            Toast.makeText(this, "选区过小，请重新选择", Toast.LENGTH_SHORT).show()
                        }
                        cancelSelection()
                    } else {
                        captureRegion()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    cancelSelection()
                    true
                }
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
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                e.printStackTrace()
            }
            selectionOverlay = null
        }
    }

    private fun captureRegion() {
        hideSelectionOverlay()
        removeFloatingWindow()

        try {
            val shutter = android.media.RingtoneManager.getDefaultUri(
                android.media.RingtoneManager.TYPE_NOTIFICATION
            )
            val ringtone = android.media.RingtoneManager.getRingtone(this, shutter)
            ringtone?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }

        handler.post {
            Toast.makeText(this, "截屏中...", Toast.LENGTH_SHORT).show()
        }

        handler.postDelayed({
            startScreenCaptureForRegion()
        }, 100)
    }

    private fun startScreenCaptureForRegion() {
        android.util.Log.d("FloatingWindow", ">>> startScreenCaptureForRegion, captureInitialized=$captureInitialized")

        if (!captureInitialized) {
            handler.post {
                Toast.makeText(this, "正在请求截图权限...", Toast.LENGTH_SHORT).show()
            }
            isWaitingForScreenshotPermission = true
            onScreenshotPermissionNeeded?.invoke()
            return
        }

        val bitmap = acquireFrame()
        if (bitmap == null) {
            handler.post {
                Toast.makeText(this, "截图失败：无法获取图像", Toast.LENGTH_SHORT).show()
            }
            showFloatingWindow()
            return
        }

        pendingBitmap = bitmap
        cropAndSendBitmap(bitmap.width, bitmap.height)
    }

    private fun cropAndSendBitmap(screenWidth: Int, screenHeight: Int) {
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
                handler.post {
                    Toast.makeText(this, "选区无效", Toast.LENGTH_SHORT).show()
                }
                bitmap.recycle()
                showFloatingWindow()
                return
            }

            val croppedBitmap = android.graphics.Bitmap.createBitmap(
                bitmap,
                cropLeft,
                cropTop,
                cropWidth,
                cropHeight
            )

            bitmap.recycle()
            pendingCroppedBitmap = croppedBitmap
            showChatOverlay(croppedBitmap)

        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "裁剪截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
            bitmap.recycle()
            showFloatingWindow()
        }
    }

    private fun showChatOverlay(croppedBitmap: android.graphics.Bitmap) {
        val imagePath = saveBitmapToTempFile(croppedBitmap)

        val chatView = ChatOverlayView(this).apply {
            setBitmap(croppedBitmap)
            onRegionSelected = {
                callAiApi(systemPrompt, imagePath)
            }
            onClose = {
                hideChatOverlay()
                croppedBitmap.recycle()
                showFloatingWindow()
            }
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        try {
            windowManager?.addView(chatView, params)
            chatOverlay = chatView
            chatView.onRegionSelected?.invoke()
        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "显示失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun hideChatOverlay() {
        chatOverlay?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                // 忽略
            }
            chatOverlay = null
        }
    }

    // ========== AI 回调方法（由 Flutter 调用）==========

    fun showAiLoading() {
        handler.post {
            chatOverlay?.showLoading()
        }
    }

    fun appendAiAnswer(chunk: String) {
        handler.post {
            chatOverlay?.appendAnswer(chunk)
        }
    }

    fun showAiError(error: String) {
        handler.post {
            chatOverlay?.showError(error)
        }
    }

    fun hideAiLoading() {
        handler.post {
            chatOverlay?.hideLoading()
        }
    }

    private fun callAiApi(question: String, imagePath: String) {
        handler.post { chatOverlay?.showLoading() }

        Thread {
            try {
                val file = File(imagePath)
                val imageBytes = FileInputStream(file).use { it.readBytes() }
                val imageBase64 = Base64.encodeToString(imageBytes, Base64.NO_WRAP)

                val messages = """
                    [
                        {"role": "system", "content": "$systemPrompt"},
                        {"role": "user", "content": [
                            {"type": "image_url", "image_url": {"url": "data:image/png;base64,$imageBase64"}},
                            {"type": "text", "text": "$question"}
                        ]}
                    ]
                """.trimIndent()

                val jsonBody = """
                    {
                        "model": "$model",
                        "messages": $messages,
                        "stream": true,
                        "thinking": {"type": "disabled"}
                    }
                """.trimIndent()

                val url = URL(apiUrl)
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Authorization", "Bearer $apiKey")
                connection.connectTimeout = 30000
                connection.readTimeout = 30000

                OutputStreamWriter(connection.outputStream).use { writer ->
                    writer.write(jsonBody)
                    writer.flush()
                }

                val responseCode = connection.responseCode
                if (responseCode != 200) {
                    handler.post {
                        chatOverlay?.showError("API 错误: $responseCode")
                        chatOverlay?.hideLoading()
                    }
                    connection.disconnect()
                    return@Thread
                }

                BufferedReader(InputStreamReader(connection.inputStream)).use { reader ->
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        line = line?.trim()
                        if (line.isNullOrEmpty()) continue

                        if (line!!.startsWith("data: ")) {
                            val data = line!!.substring(6)
                            if (data == "[DONE]") break

                            val content = parseSseData(data)
                            if (content.isNotEmpty()) {
                                handler.post {
                                    chatOverlay?.appendAnswer(content)
                                }
                            }
                        }
                    }
                }

                connection.disconnect()

                handler.post {
                    chatOverlay?.hideLoading()
                }

                try {
                    file.delete()
                } catch (e: Exception) {
                    // 忽略
                }

            } catch (e: Exception) {
                android.util.Log.e("FloatingWindow", "callAiApi error: ${e.message}", e)
                handler.post {
                    chatOverlay?.showError("请求失败: ${e.message}")
                    chatOverlay?.hideLoading()
                }
            }
        }.start()
    }

    private fun saveBitmapToTempFile(bitmap: android.graphics.Bitmap): String {
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        val file = File(cacheDir, "ai_question_$timestamp.png")
        FileOutputStream(file).use { out ->
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, out)
        }
        return file.absolutePath
    }

    private fun parseSseData(json: String): String {
        return try {
            val obj = org.json.JSONObject(json)
            val choices = obj.optJSONArray("choices")
            if (choices != null && choices.length() > 0) {
                val delta = choices.getJSONObject(0).optJSONObject("delta")
                delta?.optString("content") ?: ""
            } else ""
        } catch (e: Exception) {
            ""
        }
    }

    fun saveScreenshotToGallery(byteArray: ByteArray) {
        try {
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size)
            if (bitmap != null) {
                saveBitmap(bitmap)
                bitmap.recycle()
            }
        } catch (e: Exception) {
            android.util.Log.e("FloatingWindow", "saveScreenshotToGallery error: ${e.message}", e)
            handler.post {
                Toast.makeText(this, "保存失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
