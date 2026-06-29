package io.github.xiaodouzi.fr.native.overlay

import android.annotation.SuppressLint
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Environment
import android.os.Handler
import android.util.DisplayMetrics
import android.view.WindowManager
import android.widget.Toast
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.io.OutputStreamWriter
import java.io.BufferedReader
import java.io.InputStreamReader
import android.util.Base64
import android.graphics.Bitmap

/**
 * 截图功能模块
 */
class FloatingWindowScreenshot(
    private val context: android.content.Context,
    private val handler: Handler,
    private val windowManager: WindowManager?
) {
    private var captureImageReader: ImageReader? = null
    private var captureVirtualDisplay: VirtualDisplay? = null
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var screenDensity: Int = 0
    var captureInitialized: Boolean = false
        private set

    @SuppressLint("WrongConstant")
    fun initPersistentCapture(mediaProjection: MediaProjection) {
        if (captureInitialized) return

        val displayMetrics = DisplayMetrics()
        windowManager?.defaultDisplay?.getRealMetrics(displayMetrics)
        screenWidth = displayMetrics.widthPixels
        screenHeight = displayMetrics.heightPixels
        screenDensity = displayMetrics.densityDpi

        if (screenWidth <= 0 || screenHeight <= 0) {
            handler.post {
                Toast.makeText(context, "屏幕尺寸获取失败", Toast.LENGTH_SHORT).show()
            }
            return
        }

        mediaProjection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                releaseAllCaptureResources()
                handler.post {
                    Toast.makeText(context, "截屏权限已取消", Toast.LENGTH_SHORT).show()
                }
            }
        }, handler)

        captureImageReader = ImageReader.newInstance(
            screenWidth, screenHeight,
            PixelFormat.RGBA_8888,
            2
        )

        val surface = captureImageReader?.surface
        if (surface == null) {
            handler.post {
                Toast.makeText(context, "截图初始化失败", Toast.LENGTH_SHORT).show()
            }
            return
        }

        captureVirtualDisplay = mediaProjection.createVirtualDisplay(
            "ScreenCapturePersistent",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            surface,
            null, handler
        )

        captureInitialized = true
    }

    /**
     * 获取最近一帧的截图 Bitmap。
     *
     * 该 Bitmap 的坐标系以 MediaProjection 截屏的原点 (0, 0) 为基准，
     * 在大多数 Android 设备上等同于物理屏幕左上角（含状态栏）。
     * 但在部分 ROM 上，MediaProjection 实际截屏尺寸可能小于物理屏幕
     * （例如去掉了导航栏 / 状态栏区域），此时返回的 Bitmap 高度
     * 会小于 screenHeight，调用方应据此对 crop 坐标做归一化处理。
     */
    fun acquireFrame(): android.graphics.Bitmap? {
        if (!captureInitialized || captureImageReader == null) return null

        val image = captureImageReader?.acquireLatestImage() ?: return null
        return image.useToBitmap()
    }

    /** 最近一次截屏的真实宽高，外部 crop 逻辑需要用来归一化坐标。 */
    var capturedFrameWidth: Int = 0
        private set
    var capturedFrameHeight: Int = 0
        private set

    fun discardPendingFrames() {
        if (!captureInitialized || captureImageReader == null) return

        while (true) {
            val image = captureImageReader?.acquireLatestImage() ?: break
            image.close()
        }
    }

    fun awaitNextFrame(timeoutMs: Long = 400L, onResult: (Bitmap?) -> Unit) {
        val reader = captureImageReader
        if (!captureInitialized || reader == null) {
            handler.post { onResult(null) }
            return
        }

        var completed = false

        fun finish(bitmap: Bitmap?) {
            if (completed) return
            completed = true
            reader.setOnImageAvailableListener(null, null)
            onResult(bitmap)
        }

        reader.setOnImageAvailableListener({ imageReader ->
            val image = imageReader.acquireLatestImage() ?: return@setOnImageAvailableListener
            finish(image.useToBitmap())
        }, handler)

        handler.postDelayed({
            finish(null)
        }, timeoutMs)
    }

    private fun android.media.Image.useToBitmap(): Bitmap? {
        try {
            val planes = planes
            val buffer = planes[0].buffer
            val rowStride = planes[0].rowStride
            val pixelStride = planes[0].pixelStride
            // 注意：rowStride 在某些 GPU/驱动下可能小于 width * pixelStride
            // （虽然规范上不应当出现，但作为防御式编程，避免负数导致 Bitmap 宽度异常）
            val rawRowPadding = rowStride - width * pixelStride
            val safeRowPadding = if (rawRowPadding < 0) 0 else rawRowPadding
            val extraCols = safeRowPadding / pixelStride

            val bitmapWidth = width + extraCols
            val bitmapHeight = height

            val bitmap = Bitmap.createBitmap(
                bitmapWidth,
                bitmapHeight,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)

            // 裁剪到 image 实际尺寸（width × height），不再使用 screenWidth/screenHeight
            // 因为 MediaProjection 在部分 ROM 上截屏尺寸可能与 getRealMetrics 不一致
            val cropped = if (bitmapWidth > width || bitmapHeight > height) {
                Bitmap.createBitmap(bitmap, 0, 0, width, height)
            } else {
                bitmap
            }

            if (cropped != bitmap) bitmap.recycle()
            close()
            // 记录最近一帧的真实尺寸，供调用方在 crop 时归一化坐标
            capturedFrameWidth = width
            capturedFrameHeight = height
            return cropped
        } catch (e: Exception) {
            close()
            return null
        }
    }

    fun releaseAllCaptureResources() {
        try {
            captureVirtualDisplay?.release()
        } catch (e: Exception) { /* 忽略 */ }
        try {
            captureImageReader?.close()
        } catch (e: Exception) { /* 忽略 */ }
        captureVirtualDisplay = null
        captureImageReader = null
        captureInitialized = false
    }

    fun saveBitmap(bitmap: android.graphics.Bitmap, onSaved: ((String) -> Unit)? = null) {
        try {
            val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
            val filename = "screenshot_$timestamp.png"

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                val contentValues = android.content.ContentValues().apply {
                    put(android.provider.MediaStore.Images.Media.DISPLAY_NAME, filename)
                    put(android.provider.MediaStore.Images.Media.MIME_TYPE, "image/png")
                    put(android.provider.MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/Screenshots")
                    put(android.provider.MediaStore.Images.Media.IS_PENDING, 1)
                }

                val uri = context.contentResolver.insert(
                    android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    contentValues
                )

                uri?.let {
                    context.contentResolver.openOutputStream(it)?.use { outputStream ->
                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, outputStream)
                    }

                    contentValues.clear()
                    contentValues.put(android.provider.MediaStore.Images.Media.IS_PENDING, 0)
                    context.contentResolver.update(it, contentValues, null, null)

                    handler.post {
                        Toast.makeText(context, "截图已保存到图库", Toast.LENGTH_LONG).show()
                    }

                    onSaved?.invoke(it.toString())
                    return
                }
            }

            // Legacy
            val dir = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                "Screenshots"
            )
            if (!dir.exists()) dir.mkdirs()

            val file = File(dir, filename)
            FileOutputStream(file).use { out ->
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
            }

            val intent = android.content.Intent(android.content.Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
            intent.data = android.net.Uri.fromFile(file)
            context.sendBroadcast(intent)

            handler.post {
                Toast.makeText(context, "截图已保存到图库", Toast.LENGTH_LONG).show()
            }

            onSaved?.invoke(file.absolutePath)

        } catch (e: Exception) {
            handler.post {
                Toast.makeText(context, "保存截图失败: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun saveBitmapToTempFile(bitmap: android.graphics.Bitmap): String {
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.getDefault()).format(Date())
        val file = File(context.cacheDir, "ai_question_$timestamp.png")
        FileOutputStream(file).use { out ->
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 90, out)
        }
        return file.absolutePath
    }
}
