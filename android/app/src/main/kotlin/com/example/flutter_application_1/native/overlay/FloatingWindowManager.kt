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
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.net.Uri
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 悬浮窗管理器 - 统一管理原生悬浮窗功能
 * 包含权限检查、悬浮窗显示、截图等功能
 */
class FloatingWindowManager : Service() {

    /**
     * 选框边框视图 - 绘制半透明黑色遮罩（选区内部透明）+ 白色边框
     * 使用四个矩形绘制遮罩：上下左右包围选区
     */
    class SelectionBorderView(context: Context) : View(context) {
        val rect = Rect()
        val borderPaint = Paint().apply {
            color = Color.WHITE
            style = Paint.Style.STROKE
            strokeWidth = 3 * context.resources.displayMetrics.density
            isAntiAlias = true
        }
        val overlayPaint = Paint().apply {
            color = Color.argb(128, 0, 0, 0) // 半透明黑色
            style = Paint.Style.FILL
            isAntiAlias = true
        }

        fun updateRect(left: Int, top: Int, right: Int, bottom: Int) {
            rect.set(left, top, right, bottom)
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            if (rect.width() > 0 && rect.height() > 0) {
                val selectionRect = android.graphics.RectF(
                    rect.left.toFloat(),
                    rect.top.toFloat(),
                    rect.right.toFloat(),
                    rect.bottom.toFloat()
                )

                // 绘制四个半透明黑色矩形，围绕选区
                // 上方
                canvas.drawRect(0f, 0f, width.toFloat(), selectionRect.top, overlayPaint)
                // 下方
                canvas.drawRect(0f, selectionRect.bottom, width.toFloat(), height.toFloat(), overlayPaint)
                // 左侧
                canvas.drawRect(0f, selectionRect.top, selectionRect.left, selectionRect.bottom, overlayPaint)
                // 右侧
                canvas.drawRect(selectionRect.right, selectionRect.top, width.toFloat(), selectionRect.bottom, overlayPaint)

                // 绘制白色边框
                canvas.drawRect(selectionRect, borderPaint)
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private lateinit var handler: Handler
    private val thread = HandlerThread("FloatingWindowThread").apply { start() }

    // Selection overlay properties
    private var selectionOverlay: View? = null
    private var selectionStartX = 0
    private var selectionStartY = 0
    private var selectionEndX = 0
    private var selectionEndY = 0
    private var isSelecting = false
    private var pendingBitmap: android.graphics.Bitmap? = null
    private var pendingCroppedBitmap: android.graphics.Bitmap? = null
    private var isWaitingForScreenshotPermission = false
    private var previewOverlay: View? = null
    private var previewBackground: View? = null

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
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForeground(NOTIFICATION_ID, createNotification())
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

    /**
     * 检查悬浮窗权限
     */
    fun checkOverlayPermission(): Boolean {
        return Settings.canDrawOverlays(this)
    }

    /**
     * 显示悬浮窗
     */
    @SuppressLint("InflateParams", "ClickableViewAccessibility", "WrongConstant")
    fun showFloatingWindow(): Boolean {
        // 先检查权限
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

            // 使用更安全的 flags 组合，确保可触摸
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

            // 使用 applicationContext 创建视图，避免 context 问题
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
        // 使用 applicationContext
        val container = FrameLayout(context).apply {
            // 设置透明背景确保触摸区域正确
            setBackgroundColor(0x00000000)
            // 确保可点击
            isClickable = true
            isFocusable = true
        }

        val size = dpToPx(56)
        container.layoutParams = FrameLayout.LayoutParams(size, size)

        // 相机图标
        val imageView = ImageView(context).apply {
            setImageResource(android.R.drawable.ic_menu_camera)
            setColorFilter(0xFF87CEEB.toInt())  // 浅蓝色
            layoutParams = FrameLayout.LayoutParams(dpToPx(40), dpToPx(40)).apply {
                gravity = Gravity.CENTER
            }
        }
        container.addView(imageView)

        // 右下角截图指示器
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
                        // 忽略更新异常
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val movedX = kotlin.math.abs(event.rawX - initialTouchX)
                    val movedY = kotlin.math.abs(event.rawY - initialTouchY)

                    // 判断为点击（移动距离小于 10dp）
                    val touchSlop = 10 * resources.displayMetrics.density
                    if (movedX < touchSlop && movedY < touchSlop) {
                        val currentTime = System.currentTimeMillis()
                        // 防抖：距离上次点击超过 300ms
                        if (currentTime - lastTapTime > 300) {
                            lastTapTime = currentTime
                            showSelectionOverlay()
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
            handler.post {
                Toast.makeText(this, "截屏中...", Toast.LENGTH_SHORT).show()
            }

            val shutter = android.media.RingtoneManager.getDefaultUri(
                android.media.RingtoneManager.TYPE_NOTIFICATION
            )
            val ringtone = android.media.RingtoneManager.getRingtone(this, shutter)
            ringtone?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }

        startScreenCapture()
    }

    private fun startScreenCapture() {
        android.util.Log.d("FloatingWindow", ">>> startScreenCapture begin")
        // 先检查 mediaProjection 是否有效
        if (mediaProjection == null) {
            android.util.Log.d("FloatingWindow", "startScreenCapture: mediaProjection is null, requesting permission")
            handler.post {
                try {
                    Toast.makeText(this, "正在请求截图权限...", Toast.LENGTH_SHORT).show()
                } catch (e: Exception) {
                    // 忽略
                }
            }
            // 触发 MainActivity 请求截图权限
            onScreenshotPermissionNeeded?.invoke()
            return
        }

        try {
            val displayMetrics = DisplayMetrics()
            windowManager?.defaultDisplay?.getMetrics(displayMetrics)
            val width = displayMetrics.widthPixels
            val height = displayMetrics.heightPixels
            val density = displayMetrics.densityDpi

            android.util.Log.d("FloatingWindow", "startScreenCapture: creating ImageReader $width x $height density $density")
            imageReader?.close()
            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
            android.util.Log.d("FloatingWindow", "startScreenCapture: ImageReader created, surface=${imageReader?.surface}")

            val callback = object : MediaProjection.Callback() {
                override fun onStop() {
                    virtualDisplay?.release()
                    android.util.Log.d("FloatingWindow", "startScreenCapture: MediaProjection stopped")
                    handler.post {
                        try {
                            Toast.makeText(this@FloatingWindowManager, "截图权限已取消", Toast.LENGTH_SHORT).show()
                        } catch (e: Exception) {
                            // 忽略 Toast 异常
                        }
                    }
                }
            }

            mediaProjection?.registerCallback(callback, handler)
            android.util.Log.d("FloatingWindow", "startScreenCapture: registered callback")

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
            android.util.Log.d("FloatingWindow", "startScreenCapture: virtualDisplay created")

            handler.postDelayed({
                android.util.Log.d("FloatingWindow", "startScreenCapture: calling takePicture")
                takePicture()
            }, 100)

        } catch (e: Exception) {
            android.util.Log.e("FloatingWindow", "startScreenCapture error: ${e.message}", e)
            e.printStackTrace()
            handler.post {
                try {
                    Toast.makeText(this, "截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
                } catch (e2: Exception) {
                    // 忽略
                }
            }
        }
    }

    private fun takePicture() {
        android.util.Log.d("FloatingWindow", ">>> takePicture begin")
        try {
            val image = imageReader?.acquireLatestImage()
            android.util.Log.d("FloatingWindow", "takePicture: acquired image=$image")
            image?.let {
                val planes = it.planes
                val buffer = planes[0].buffer
                val rowStride = planes[0].rowStride
                val pixelStride = planes[0].pixelStride
                val rowPadding = rowStride - it.width * pixelStride

                val bitmap = android.graphics.Bitmap.createBitmap(
                    it.width + rowPadding / pixelStride,
                    it.height,
                    android.graphics.Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(buffer)

                val finalBitmap = android.graphics.Bitmap.createBitmap(
                    bitmap,
                    0,
                    0,
                    it.width,
                    it.height
                )

                saveBitmap(finalBitmap)
                bitmap.recycle()
                if (finalBitmap != bitmap) finalBitmap.recycle()
                it.close()
            }
        } catch (e: Exception) {
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

    private fun saveBitmap(bitmap: android.graphics.Bitmap) {
        try {
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val filename = "screenshot_$timestamp.png"
            android.util.Log.d("FloatingWindow", "saveBitmap: filename=$filename SDK=${Build.VERSION.SDK_INT}")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10+ 使用 MediaStore API
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

                    // 标记完成
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

            // Android 9 及以下使用传统方式
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

            // 通知媒体库更新
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
            // 忽略广播异常
        }
    }

    fun setMediaProjection(mediaProjection: MediaProjection?) {
        this.mediaProjection = mediaProjection
        // 如果正在等待截图权限，权限授予后自动继续截图
        if (mediaProjection != null && isWaitingForScreenshotPermission) {
            android.util.Log.d("FloatingWindow", "setMediaProjection: permission granted, continuing screenshot")
            isWaitingForScreenshotPermission = false
            handler.post {
                startScreenCaptureForRegion()
            }
        }
    }

    private fun releaseMediaProjection() {
        try {
            mediaProjection?.stop()
        } catch (e: Exception) {
            // 忽略
        }
        try {
            virtualDisplay?.release()
        } catch (e: Exception) {
            // 忽略
        }
        try {
            imageReader?.close()
        } catch (e: Exception) {
            // 忽略
        }
        mediaProjection = null
        virtualDisplay = null
        imageReader = null
    }

    /**
     * 只释放 imageReader 和 virtualDisplay，保留 mediaProjection
     */
    private fun releaseImageReaderAndVirtualDisplay() {
        try {
            virtualDisplay?.release()
        } catch (e: Exception) {
            // 忽略
        }
        try {
            imageReader?.close()
        } catch (e: Exception) {
            // 忽略
        }
        virtualDisplay = null
        imageReader = null
    }

    fun hideFloatingWindow() {
        removeFloatingWindow()
    }

    fun isFloatingWindowShowing(): Boolean {
        return floatingView != null
    }

    /**
     * 显示区域选择遮罩
     */
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

            // 隐藏悬浮窗
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

        // 添加选框边框视图（内部已包含遮罩和挖空逻辑）
        val borderView = SelectionBorderView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        container.addView(borderView)

        // 触摸事件直接监听在 container 上
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
                        showFloatingWindow()
                        hideSelectionOverlay()
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

    /**
     * 取消选区选择
     */
    private fun cancelSelection() {
        isSelecting = false
        hideSelectionOverlay()
        showFloatingWindow()
    }

    /**
     * 隐藏选区遮罩
     */
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

    /**
     * 触发区域截图
     */
    private fun captureRegion() {
        // 先隐藏选框
        hideSelectionOverlay()

        // 播放截图音效
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

        startScreenCaptureForRegion()
    }

    /**
     * 全屏截图供裁剪
     */
    private fun startScreenCaptureForRegion() {
        android.util.Log.d("FloatingWindow", ">>> startScreenCaptureForRegion, mediaProjection=$mediaProjection")
        if (mediaProjection == null) {
            handler.post {
                Toast.makeText(this, "正在请求截图权限...", Toast.LENGTH_SHORT).show()
            }
            isWaitingForScreenshotPermission = true
            onScreenshotPermissionNeeded?.invoke()
            return
        }

        try {
            val displayMetrics = DisplayMetrics()
            windowManager?.defaultDisplay?.getMetrics(displayMetrics)
            val width = displayMetrics.widthPixels
            val height = displayMetrics.heightPixels
            val density = displayMetrics.densityDpi

            // 只释放 imageReader 和 virtualDisplay，保留 mediaProjection
            releaseImageReaderAndVirtualDisplay()

            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

            val callback = object : MediaProjection.Callback() {
                override fun onStop() {
                    virtualDisplay?.release()
                    handler.post {
                        Toast.makeText(this@FloatingWindowManager, "截图权限已取消", Toast.LENGTH_SHORT).show()
                    }
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

            // 增加延迟到 300ms 确保 ImageReader 准备好
            handler.postDelayed({
                takePictureForRegion(width, height)
            }, 300)

        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun takePictureForRegion(screenWidth: Int, screenHeight: Int) {
        android.util.Log.d("FloatingWindow", ">>> takePictureForRegion begin, imageReader=$imageReader")
        try {
            val image = imageReader?.acquireLatestImage()
            android.util.Log.d("FloatingWindow", "takePictureForRegion: acquired image=$image")
            image?.let {
                val planes = it.planes
                val buffer = planes[0].buffer
                val rowStride = planes[0].rowStride
                val pixelStride = planes[0].pixelStride
                val rowPadding = rowStride - it.width * pixelStride

                val bitmap = android.graphics.Bitmap.createBitmap(
                    it.width + rowPadding / pixelStride,
                    it.height,
                    android.graphics.Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(buffer)

                val fullBitmap = android.graphics.Bitmap.createBitmap(
                    bitmap,
                    0,
                    0,
                    it.width,
                    it.height
                )

                // 保存全屏截图用于后续处理
                pendingBitmap = fullBitmap
                bitmap.recycle()
                it.close()

                // 裁剪并发送
                cropAndSendBitmap(screenWidth, screenHeight)
            } ?: run {
                android.util.Log.e("FloatingWindow", "takePictureForRegion: image is null, cannot capture")
                handler.post {
                    Toast.makeText(this, "截图失败：无法获取图像", Toast.LENGTH_SHORT).show()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "保存截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    /**
     * 裁剪选区并发送截图
     */
    private fun cropAndSendBitmap(screenWidth: Int, screenHeight: Int) {
        val bitmap = pendingBitmap ?: return
        pendingBitmap = null

        try {
            // 直接使用屏幕像素坐标，不需要除以 density
            // event.rawX/Y 是屏幕像素，bitmap 尺寸也是屏幕像素
            val left = minOf(selectionStartX, selectionEndX)
            val top = minOf(selectionStartY, selectionEndY)
            val right = maxOf(selectionStartX, selectionEndX)
            val bottom = maxOf(selectionStartY, selectionEndY)

            // 确保坐标在有效范围内
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
                return
            }

            // 裁剪_bitmap
            val croppedBitmap = android.graphics.Bitmap.createBitmap(
                bitmap,
                cropLeft,
                cropTop,
                cropWidth,
                cropHeight
            )

            bitmap.recycle()

            // 保存裁剪后的 bitmap 用于预览和保存
            pendingCroppedBitmap = croppedBitmap

            // 显示原生预览视图
            showPreviewOverlay(croppedBitmap)

        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "裁剪截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    /**
     * 显示预览视图
     */
    private fun showPreviewOverlay(croppedBitmap: android.graphics.Bitmap) {
        // 创建遮罩背景
        val backgroundView = View(this).apply {
            setBackgroundColor(Color.argb(180, 0, 0, 0))
        }

        // 创建预览容器
        val previewContainer = FrameLayout(this).apply {
            setBackgroundColor(0xFF2A2A2A.toInt())
        }

        // 缩放bitmap以适应屏幕（最大宽度为屏幕宽度的90%）
        val maxWidth = (resources.displayMetrics.widthPixels * 0.9).toInt()
        val maxHeight = (resources.displayMetrics.heightPixels * 0.5).toInt()
        val scaledBitmap = scaleBitmapToFit(croppedBitmap, maxWidth, maxHeight)

        // 预览图像
        val imageView = ImageView(this).apply {
            setImageBitmap(scaledBitmap)
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                gravity = Gravity.CENTER_HORIZONTAL or Gravity.TOP
                topMargin = dpToPx(50)
            }
        }
        previewContainer.addView(imageView)

        // 按钮容器
        val buttonContainer = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                dpToPx(80)
            ).apply {
                gravity = Gravity.BOTTOM
                bottomMargin = dpToPx(100)
            }
        }

        // 取消按钮
        val cancelButton = TextView(this).apply {
            text = "取消"
            textSize = 16f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(180, 255, 68, 68))
            setPadding(dpToPx(24), dpToPx(12), dpToPx(24), dpToPx(12))
        }
        cancelButton.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER
            marginStart = dpToPx(80)
        }
        cancelButton.setOnClickListener {
            hidePreviewOverlay()
            pendingCroppedBitmap?.recycle()
            pendingCroppedBitmap = null
            if (scaledBitmap != croppedBitmap) {
                scaledBitmap.recycle()
            }
            showFloatingWindow()
        }

        // 保存按钮
        val saveButton = TextView(this).apply {
            text = "保存"
            textSize = 16f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            setBackgroundColor(Color.argb(180, 76, 175, 80))
            setPadding(dpToPx(24), dpToPx(12), dpToPx(24), dpToPx(12))
        }
        saveButton.layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER
            marginEnd = dpToPx(80)
        }
        saveButton.setOnClickListener {
            // 保存截图
            pendingCroppedBitmap?.let { bmp ->
                saveBitmap(bmp)
                bmp.recycle()
            }
            pendingCroppedBitmap = null
            hidePreviewOverlay()
            if (scaledBitmap != croppedBitmap) {
                scaledBitmap.recycle()
            }
            showFloatingWindow()
        }

        buttonContainer.addView(cancelButton)
        buttonContainer.addView(saveButton)
        previewContainer.addView(buttonContainer)

        // 添加到窗口
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )

        try {
            windowManager?.addView(backgroundView, params)
            windowManager?.addView(previewContainer, params)
            previewOverlay = previewContainer
            previewBackground = backgroundView
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * 缩放bitmap以适应指定尺寸
     */
    private fun scaleBitmapToFit(bitmap: android.graphics.Bitmap, maxWidth: Int, maxHeight: Int): android.graphics.Bitmap {
        val width = bitmap.width
        val height = bitmap.height

        if (width <= maxWidth && height <= maxHeight) {
            return bitmap
        }

        val ratio = minOf(maxWidth.toFloat() / width, maxHeight.toFloat() / height)
        val newWidth = (width * ratio).toInt()
        val newHeight = (height * ratio).toInt()

        return android.graphics.Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
    }

    /**
     * 隐藏预览视图
     */
    private fun hidePreviewOverlay() {
        previewOverlay?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                // 忽略
            }
            previewOverlay = null
        }
        previewBackground?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Exception) {
                // 忽略
            }
            previewBackground = null
        }
    }

    /**
     * 发送区域截图数据给 Flutter
     */
    private fun notifyFlutterRegionCaptured(byteArray: ByteArray) {
        try {
            val intent = Intent("com.example.flutter_application_1.REGION_CAPTURED").apply {
                putExtra("data", byteArray)
                putExtra("left", minOf(selectionStartX, selectionEndX))
                putExtra("top", minOf(selectionStartY, selectionEndY))
                putExtra("right", maxOf(selectionStartX, selectionEndX))
                putExtra("bottom", maxOf(selectionStartY, selectionEndY))
                setPackage(packageName)
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * 保存截图到图库（供 Flutter 调用）
     */
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