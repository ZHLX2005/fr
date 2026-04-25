package io.github.xiaodouzi.fr.native.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.view.LayoutInflater
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.ScrollView
import io.github.xiaodouzi.fr.R

/**
 * 选框边框视图 - 绘制半透明黑色遮罩（选区内部透明）+ 白色边框
 * 未选中时绘制全屏半透明遮罩，选中时绘制四个矩形围绕选区
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
            // 有选区时：绘制四个矩形围绕选区（中间透明）
            val selectionRect = android.graphics.RectF(
                rect.left.toFloat(),
                rect.top.toFloat(),
                rect.right.toFloat(),
                rect.bottom.toFloat()
            )
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
        } else {
            // 无选区时：绘制全屏半透明遮罩
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), overlayPaint)
        }
    }
}

/**
 * AI 问答视图 - 截图预览 + 问题输入 + AI 回答
 */
class ChatOverlayView(context: Context) : FrameLayout(context) {
    private var croppedBitmap: android.graphics.Bitmap? = null
    private var answerText: android.widget.TextView? = null
    private var loadingIndicator: ProgressBar? = null

    var onRegionSelected: (() -> Unit)? = null  // 区域已选择，自动发送
    var onClose: (() -> Unit)? = null

    init {
        // 加载布局
        LayoutInflater.from(context).inflate(R.layout.chat_overlay, this, true)

        // 查找视图
        answerText = findViewById(R.id.answer_text)
        loadingIndicator = findViewById(R.id.loading)

        val previewImage = findViewById<ImageView>(R.id.preview_image)
        croppedBitmap?.let { previewImage?.setImageBitmap(it) }

        val closeButton = findViewById<Button>(R.id.btn_close)

        closeButton?.setOnClickListener {
            onClose?.invoke()
        }
    }

    fun setBitmap(bitmap: android.graphics.Bitmap) {
        croppedBitmap = bitmap
        findViewById<ImageView>(R.id.preview_image)?.setImageBitmap(bitmap)
    }

    fun showLoading() {
        loadingIndicator?.visibility = View.VISIBLE
        answerText?.text = ""
    }

    fun appendAnswer(text: String) {
        loadingIndicator?.visibility = View.GONE
        val current = answerText?.text ?: ""
        answerText?.text = "$current$text"
        // 自动滚动到底部
        (answerText?.parent as? ScrollView)?.post {
            (answerText?.parent as? ScrollView)?.fullScroll(View.FOCUS_DOWN)
        }
    }

    fun showError(message: String) {
        loadingIndicator?.visibility = View.GONE
        answerText?.text = "错误: $message"
    }

    fun hideLoading() {
        loadingIndicator?.visibility = View.GONE
    }

    fun clearAnswer() {
        answerText?.text = ""
    }
}
