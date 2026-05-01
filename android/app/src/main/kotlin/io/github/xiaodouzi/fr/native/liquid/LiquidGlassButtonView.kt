package io.github.xiaodouzi.fr.native.liquid

import android.content.Context
import android.graphics.*
import android.os.Build
import android.view.MotionEvent
import android.view.View

/**
 * 原生 Android 液态玻璃按钮视图
 * 实现类似 iOS 26 Liquid Glass 的按钮效果
 */
class LiquidGlassButtonView(context: Context) : View(context) {

    // 画笔
    private val glassPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // 触摸状态
    private var isPressed = false

    // 动画
    private var animationProgress = 0f
    private val animator = android.animation.ValueAnimator.ofFloat(0f, 1f)

    init {
        // 设置阴影
        shadowPaint.apply {
            color = Color.argb(40, 0, 0, 0)
            maskFilter = BlurMaskFilter(30f, BlurMaskFilter.Blur.NORMAL)
        }

        // 设置玻璃边框
        borderPaint.apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.5f
            color = Color.argb(51, 255, 255, 255)
        }

        // 文字画笔
        textPaint.apply {
            color = Color.WHITE
            textSize = 16f * resources.displayMetrics.scaledDensity
            textAlign = Paint.Align.CENTER
        }

        // 动画
        animator.duration = 150
        animator.addUpdateListener {
            animationProgress = it.animatedValue as Float
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val w = width.toFloat()
        val h = height.toFloat()

        if (w <= 0 || h <= 0) return

        drawLiquidGlass(canvas, w, h)
    }

    private fun drawLiquidGlass(canvas: Canvas, w: Float, h: Float) {
        val centerX = w / 2
        val centerY = h / 2

        val glassWidth = w * 0.8f
        val glassHeight = 60f
        val cornerRadius = 30f

        val scale = if (isPressed) 0.95f + (animationProgress * 0.05f) else 1f
        val scaledWidth = glassWidth * scale
        val scaledHeight = glassHeight * scale
        val scaledLeft = centerX - scaledWidth / 2
        val scaledTop = centerY - scaledHeight / 2
        val scaledRight = centerX + scaledWidth / 2
        val scaledBottom = centerY + scaledHeight / 2

        val rect = RectF(scaledLeft, scaledTop, scaledRight, scaledBottom)
        val path = Path().apply {
            addRoundRect(rect, cornerRadius, cornerRadius, Path.Direction.CW)
        }

        // 绘制阴影
        canvas.save()
        canvas.clipPath(path, Region.Op.INTERSECT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            shadowPaint.maskFilter = BlurMaskFilter(40f * scale, BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawRoundRect(
            RectF(scaledLeft, scaledTop + 10, scaledRight, scaledBottom + 10),
            cornerRadius,
            cornerRadius,
            shadowPaint
        )
        canvas.restore()

        // 绘制玻璃渐变背景
        val glassGradient = LinearGradient(
            scaledLeft, scaledTop, scaledRight, scaledBottom,
            intArrayOf(
                Color.argb(64, 255, 255, 255),
                Color.argb(38, 255, 255, 255),
            ),
            floatArrayOf(0f, 1f),
            Shader.TileMode.CLAMP
        )
        glassPaint.shader = glassGradient
        glassPaint.style = Paint.Style.FILL

        canvas.drawPath(path, glassPaint)

        // 绘制高光边框
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val highlightShader = LinearGradient(
                scaledLeft, scaledTop,
                scaledLeft, scaledBottom,
                intArrayOf(
                    Color.argb(77, 255, 255, 255),
                    Color.argb(26, 255, 255, 255),
                    Color.argb(0, 255, 255, 255)
                ),
                floatArrayOf(0f, 0.3f, 1f),
                Shader.TileMode.CLAMP
            )
            borderPaint.shader = highlightShader
            borderPaint.strokeWidth = 1.5f * scale
            canvas.drawPath(path, borderPaint)
        } else {
            canvas.drawPath(path, borderPaint)
        }

        // 绘制文字
        canvas.drawText("液态玻璃按钮", centerX, centerY + textPaint.textSize / 3, textPaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                isPressed = true
                animator.start()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                isPressed = false
                animator.start()
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    fun destroy() {
        animator.cancel()
    }
}
