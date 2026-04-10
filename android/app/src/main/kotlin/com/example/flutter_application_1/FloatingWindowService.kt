package com.example.flutter_application_1

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
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
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class FloatingWindowService : Service() {

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler = Handler(Looper.getMainLooper())

    companion object {
        const val CHANNEL_ID = "FloatingWindowChannel"
        const val NOTIFICATION_ID = 1
        const val ACTION_START = "com.example.flutter_application_1.START_FLOATING"
        const val ACTION_STOP = "com.example.flutter_application_1.STOP_FLOATING"

        private var instance: FloatingWindowService? = null

        fun getInstance(): FloatingWindowService? = instance
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
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        removeFloatingWindow()
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
        val stopIntent = Intent(this, FloatingWindowService::class.java).apply {
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

    @SuppressLint("InflateParams", "ClickableViewAccessibility")
    private fun showFloatingWindow() {
        if (floatingView != null) return

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 0
            y = 200
        }

        floatingView = View.inflate(this, android.R.layout.simple_list_item_1, null).apply {
            setBackgroundColor(0xFF2196F3.toInt())
            minimumWidth = 120
            minimumHeight = 120

            val imageView = ImageView(this@FloatingWindowService).apply {
                setImageResource(android.R.drawable.ic_menu_camera)
                setColorFilter(0xFFFFFFFF.toInt())
                layoutParams = android.view.ViewGroup.LayoutParams(80, 80)
            }
            (this as android.view.ViewGroup).addView(imageView)

            var initialX = 0
            var initialY = 0
            var initialTouchX = 0f
            var initialTouchY = 0f

            setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        params.x = initialX - (event.rawX - initialTouchX).toInt()
                        params.y = initialY + (event.rawY - initialTouchY).toInt()
                        windowManager?.updateViewLayout(floatingView, params)
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (kotlin.math.abs(event.rawX - initialTouchX) < 50 &&
                            kotlin.math.abs(event.rawY - initialTouchY) < 50
                        ) {
                            performClick()
                            captureScreen()
                        }
                        true
                    }
                    else -> false
                }
            }

            setOnClickListener {
                captureScreen()
            }
        }

        windowManager?.addView(floatingView, params)
    }

    private fun removeFloatingWindow() {
        floatingView?.let {
            windowManager?.removeView(it)
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

        startCapture()
    }

    @SuppressLint("WrongConstant")
    private fun startCapture() {
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
                }
            }

            if (mediaProjection == null) {
                // 需要在 Activity 中预先授权，这里只是演示
            }
        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                Toast.makeText(this, "截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
