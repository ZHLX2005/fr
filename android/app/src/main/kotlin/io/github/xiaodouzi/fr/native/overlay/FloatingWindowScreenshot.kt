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

        captureVirtualDisplay = mediaProjection.createVirtualDisplay(
            "ScreenCapturePersistent",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            captureImageReader!!.surface,
            null, handler
        )

        captureInitialized = true
    }

    fun acquireFrame(): android.graphics.Bitmap? {
        if (!captureInitialized || captureImageReader == null) return null

        val image = captureImageReader?.acquireLatestImage() ?: return null

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
            image.close()
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
