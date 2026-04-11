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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
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
import com.example.flutter_application_1.MainActivity
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

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var params: WindowManager.LayoutParams? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler = Handler(Looper.getMainLooper())

    companion object {
        const val CHANNEL_ID = "FloatingWindowChannel"
        const val NOTIFICATION_ID = 1
        const val ACTION_START = "com.example.flutter_application_1.START_FLOATING"
        const val ACTION_STOP = "com.example.flutter_application_1.STOP_FLOATING"
        const val ACTION_CAPTURE = "com.example.flutter_application_1.CAPTURE_SCREEN"

        private var instance: FloatingWindowManager? = null

        fun getInstance(): FloatingWindowManager? = instance

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
     * @return true 有权限, false 无权限
     */
    fun checkOverlayPermission(): Boolean {
        return Settings.canDrawOverlays(this)
    }

    /**
     * 显示悬浮窗
     * @return true 成功, false 失败（无权限）
     */
    @SuppressLint("InflateParams", "ClickableViewAccessibility")
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

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 50
            y = 200
        }

        // 创建悬浮窗视图
        floatingView = createFloatingView()

        try {
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
    private fun createFloatingView(): View {
        // 使用自定义布局
        val container = FrameLayout(this).apply {
            setBackgroundResource(android.R.drawable.screen_background_dark)
            alpha = 0.95f
        }

        val size = dpToPx(56)
        container.layoutParams = FrameLayout.LayoutParams(size, size)

        val imageView = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_camera)
            setColorFilter(0xFFFFFFFF.toInt())
            layoutParams = FrameLayout.LayoutParams(dpToPx(40), dpToPx(40)).apply {
                gravity = Gravity.CENTER
            }
        }
        container.addView(imageView)

        // 添加截图图标
        val captureIcon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_crop)
            setColorFilter(0xFF4CAF50.toInt())
            layoutParams = FrameLayout.LayoutParams(dpToPx(20), dpToPx(20)).apply {
                gravity = Gravity.BOTTOM or Gravity.END
                bottomMargin = dpToPx(2)
                rightMargin = dpToPx(-4)
            }
        }
        container.addView(captureIcon)

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f

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
                    layoutParams.x = initialX - (event.rawX - initialTouchX).toInt()
                    layoutParams.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager?.updateViewLayout(floatingView, layoutParams)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val movedX = kotlin.math.abs(event.rawX - initialTouchX)
                    val movedY = kotlin.math.abs(event.rawY - initialTouchY)
                    if (movedX < 50 && movedY < 50) {
                        // 点击事件
                        container.performClick()
                        captureScreen()
                    }
                    true
                }
                else -> false
            }
        }

        container.setOnClickListener {
            captureScreen()
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
        Toast.makeText(this, "截屏中...", Toast.LENGTH_SHORT).show()

        try {
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
        try {
            val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

            val displayMetrics = DisplayMetrics()
            windowManager?.defaultDisplay?.getMetrics(displayMetrics)
            val width = displayMetrics.widthPixels
            val height = displayMetrics.heightPixels
            val density = displayMetrics.densityDpi

            imageReader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)

            val callback = object : MediaProjection.Callback() {
                override fun onStop() {
                    virtualDisplay?.release()
                    handler.post {
                        Toast.makeText(this@FloatingWindowManager, "截图权限已取消", Toast.LENGTH_SHORT).show()
                    }
                }
            }

            // 检查是否已有 mediaProjection
            if (mediaProjection == null) {
                // 需要在 Activity 中预先授权
                handler.post {
                    Toast.makeText(this, "需要先授权截图权限", Toast.LENGTH_LONG).show()
                }
                return
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

            // 延迟获取截图
            handler.postDelayed({
                takePicture()
            }, 100)

        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun takePicture() {
        try {
            val image = imageReader?.acquireLatestImage()
            image?.let {
                val planes = it.planes
                val buffer = planes[0].buffer
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - it.width * planes[0].pixelStride

                val bitmap = android.graphics.Bitmap.createBitmap(
                    it.width + rowPadding / planes[0].pixelStride,
                    it.height,
                    android.graphics.Bitmap.Config.ARGB_8888
                )
                bitmap.copyPixelsFromBuffer(buffer)

                // 裁剪到实际显示区域
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
                Toast.makeText(this, "保存截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun saveBitmap(bitmap: android.graphics.Bitmap) {
        try {
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val filename = "screenshot_$timestamp.png"

            val dir = File(filesDir, "screenshots")
            if (!dir.exists()) {
                dir.mkdirs()
            }

            val file = File(dir, filename)
            FileOutputStream(file).use { out ->
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
            }

            handler.post {
                Toast.makeText(this, "截图已保存: $filename", Toast.LENGTH_LONG).show()
            }

            // 通知 Flutter
            notifyFlutterScreenshot(file.absolutePath)

        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "保存截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun notifyFlutterScreenshot(path: String) {
        // 通过广播通知 Flutter
        val intent = Intent("com.example.flutter_application_1.SCREENSHOT_COMPLETED").apply {
            putExtra("path", path)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    }

    /**
     * 设置 MediaProjection（需要在 Activity 中授权后调用）
     */
    fun setMediaProjection(mediaProjection: MediaProjection?) {
        this.mediaProjection = mediaProjection
    }

    private fun releaseMediaProjection() {
        mediaProjection?.stop()
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection = null
        virtualDisplay = null
        imageReader = null
    }

    fun hideFloatingWindow() {
        removeFloatingWindow()
    }

    fun isFloatingWindowShowing(): Boolean {
        return floatingView != null
    }
}