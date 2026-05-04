package io.github.xiaodouzi.fr.native.pigment

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.media.projection.MediaProjection
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat
import io.github.xiaodouzi.fr.native.overlay.FloatingWindowScreenshot
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class PigmentFloatingManager : Service() {
    private val pickerCaptureDelayMs = 80L
    private lateinit var handler: Handler
    private val mainHandler = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("PigmentFloatingThread").apply { start() }

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var panelView: View? = null
    private var pickerView: View? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var panelParams: WindowManager.LayoutParams? = null
    private var pickerParams: WindowManager.LayoutParams? = null
    private var mediaProjection: MediaProjection? = null
    private lateinit var screenshot: FloatingWindowScreenshot
    private var currentColorLabel: TextView? = null
    private var paletteChipsRow: LinearLayout? = null
    private var panelCollapsed = false

    private var currentColor: Int = Color.parseColor("#0D1B44")
    private val strokes = mutableListOf<PaintStroke>()
    private val redo = mutableListOf<PaintStroke>()
    private val palette = mutableListOf(
        Color.parseColor("#0D1B44"),
        Color.parseColor("#FFEC04"),
        Color.parseColor("#FFD000"),
        Color.parseColor("#190059"),
        Color.parseColor("#E12301"),
        Color.parseColor("#80022E"),
        Color.parseColor("#F9FAF9"),
    )
    private var brushRadius = 18f
    private var wetness = 0.36f
    private var pendingPickerAfterPermission = false

    companion object {
        const val CHANNEL_ID = "PigmentFloatingChannel"
        const val NOTIFICATION_ID = 11
        const val ACTION_START = "io.github.xiaodouzi.fr.START_PIGMENT_FLOATING"
        const val ACTION_STOP = "io.github.xiaodouzi.fr.STOP_PIGMENT_FLOATING"
        private var instance: PigmentFloatingManager? = null
        var onScreenshotPermissionNeeded: (() -> Unit)? = null

        fun getInstance(): PigmentFloatingManager? = instance
        fun canDrawOverlays(context: Context): Boolean = Settings.canDrawOverlays(context)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        handler = Handler(thread.looper)
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        screenshot = FloatingWindowScreenshot(this, handler, windowManager)
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                promoteToForeground()
                showBubble()
            }
            ACTION_STOP -> stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        removeAllViews()
        screenshot.releaseAllCaptureResources()
        mediaProjection?.stop()
        thread.quitSafely()
        instance = null
    }

    fun promoteToForeground() {
        startForeground(NOTIFICATION_ID, createNotification())
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Pigment Overlay",
                NotificationManager.IMPORTANCE_LOW,
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val stopIntent = Intent(this, PigmentFloatingManager::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Pigment Palette")
            .setContentText("Floating bubble and native palette are active")
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Stop",
                stopPendingIntent,
            )
            .setOngoing(true)
            .build()
    }

    fun showBubble(): Boolean {
        if (!Settings.canDrawOverlays(this)) return false
        if (bubbleView != null) return true

        val size = dp(56)
        bubbleParams = WindowManager.LayoutParams(
            size,
            size,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(16)
            y = dp(220)
        }

        bubbleView = createBubbleView()
        windowManager?.addView(bubbleView, bubbleParams)
        return true
    }

    private fun createBubbleView(): View {
        val view = FrameLayout(this)
        view.layoutParams = FrameLayout.LayoutParams(dp(56), dp(56))
        view.background = BubbleDrawable { currentColor }

        val icon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_edit)
            setColorFilter(bestOnColor(currentColor))
            layoutParams = FrameLayout.LayoutParams(dp(24), dp(24), Gravity.CENTER)
        }
        view.addView(icon)

        var downX = 0f
        var downY = 0f
        var initialX = 0
        var initialY = 0

        view.setOnTouchListener { _, event ->
            val params = bubbleParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    initialX = params.x
                    initialY = params.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = initialX + (event.rawX - downX).toInt()
                    params.y = initialY + (event.rawY - downY).toInt()
                    safeUpdate(bubbleView, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    val moved = abs(event.rawX - downX) > dp(4) || abs(event.rawY - downY) > dp(4)
                    if (!moved) togglePanel() else snapBubbleToEdge()
                    true
                }
                else -> false
            }
        }

        return view
    }

    private fun snapBubbleToEdge() {
        val params = bubbleParams ?: return
        val metrics = resources.displayMetrics
        val targetX = if (params.x + dp(28) < metrics.widthPixels / 2) dp(12) else metrics.widthPixels - dp(68)
        params.x = targetX
        params.y = params.y.coerceIn(dp(96), metrics.heightPixels - dp(96))
        safeUpdate(bubbleView, params)
    }

    private fun togglePanel() {
        if (panelView == null) showPanel() else hidePanel()
    }

    private fun showPanel() {
        if (panelView != null) return
        val metrics = resources.displayMetrics
        panelParams = WindowManager.LayoutParams(
            dp(360),
            panelHeightForState(),
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val bubble = bubbleParams
            val openRight = (bubble?.x ?: 0) < metrics.widthPixels / 2
            x = if (openRight) dp(84) else metrics.widthPixels - dp(372)
            val panelHeight = panelHeightForState()
            y = (bubble?.y ?: dp(160)).coerceIn(dp(96), metrics.heightPixels - panelHeight - dp(12))
        }
        panelView = createPanelView()
        windowManager?.addView(panelView, panelParams)
        bubbleView?.visibility = View.INVISIBLE
    }

    private fun hidePanel() {
        panelView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
        }
        panelView = null
        panelParams = null
        currentColorLabel = null
        paletteChipsRow = null
        bubbleView?.visibility = View.VISIBLE
    }

    private fun createPanelView(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = PanelDrawable()
        }

        var downX = 0f
        var downY = 0f
        var initialX = 0
        var initialY = 0

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setOnTouchListener { _, event ->
                val params = panelParams ?: return@setOnTouchListener false
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        downX = event.rawX
                        downY = event.rawY
                        initialX = params.x
                        initialY = params.y
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val metrics = resources.displayMetrics
                        val panelWidth = panelView?.width ?: params.width
                        val panelHeight = panelView?.height ?: params.height
                        val nextX = initialX + (event.rawX - downX).toInt()
                        val nextY = initialY + (event.rawY - downY).toInt()
                        params.x = nextX.coerceIn(dp(8), max(dp(8), metrics.widthPixels - panelWidth - dp(8)))
                        params.y = nextY.coerceIn(dp(32), max(dp(32), metrics.heightPixels - panelHeight - dp(8)))
                        safeUpdate(panelView, params)
                        true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> true
                    else -> false
                }
            }
        }

        val title = TextView(this).apply {
            text = "调色板"
            textSize = 18f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#231A16"))
        }
        header.addView(title, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        val collapseToggle = ImageButton(this).apply {
            setImageResource(
                if (panelCollapsed) {
                    android.R.drawable.arrow_down_float
                } else {
                    android.R.drawable.arrow_up_float
                },
            )
            background = null
            setOnClickListener { togglePanelCollapsed() }
        }
        header.addView(collapseToggle)

        val close = ImageButton(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            background = null
            setOnClickListener { hidePanel() }
        }
        header.addView(close)
        root.addView(header)

        val current = TextView(this).apply {
            text = currentColorText()
            setTextColor(Color.parseColor("#6B5B4E"))
            textSize = 12f
        }
        currentColorLabel = current
        root.addView(current)

        val tools = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val pickerBtn = panelButton("取色") { enterPickerMode() }
        tools.addView(pickerBtn, LinearLayout.LayoutParams(0, dp(40), 1f))
        if (!panelCollapsed) {
            val undoBtn = panelButton("撤销") { undoStroke() }
            val redoBtn = panelButton("重做") { redoStroke() }
            val clearBtn = panelButton("清空") { clearCanvas() }
            tools.addView(undoBtn, LinearLayout.LayoutParams(0, dp(40), 1f))
            tools.addView(redoBtn, LinearLayout.LayoutParams(0, dp(40), 1f))
            tools.addView(clearBtn, LinearLayout.LayoutParams(0, dp(40), 1f))
        }
        root.addView(space(12))
        root.addView(tools)

        if (!panelCollapsed) {
            val brushLabel = TextView(this).apply {
                text = "笔触 ${brushRadius.toInt()}"
                setTextColor(Color.parseColor("#56483D"))
            }
            root.addView(space(12))
            root.addView(brushLabel)
            val brushSeek = SeekBar(this).apply {
                max = 26
                progress = (brushRadius - 8).toInt()
                setOnSeekBarChangeListener(simpleSeek { value ->
                    brushRadius = 8f + value
                    brushLabel.text = "笔触 ${brushRadius.toInt()}"
                })
            }
            root.addView(brushSeek)

            val wetLabel = TextView(this).apply {
                text = "湿度 ${(wetness * 100).toInt()}"
                setTextColor(Color.parseColor("#56483D"))
            }
            root.addView(wetLabel)
            val wetSeek = SeekBar(this).apply {
                max = 80
                progress = (wetness * 100).toInt()
                setOnSeekBarChangeListener(simpleSeek { value ->
                    wetness = value / 100f
                    wetLabel.text = "湿度 ${(wetness * 100).toInt()}"
                })
            }
            root.addView(wetSeek)
        }

        root.addView(space(12))
        val canvas = PigmentCanvasView(this).apply {
            minimumHeight = dp(220)
            onColorConsumed = { sampled ->
                currentColor = sampled
                refreshCurrentColorUi()
            }
        }
        this.canvas = canvas
        root.addView(canvas, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            0,
            1f,
        ))

        if (!panelCollapsed) {
            root.addView(space(12))
            val paletteTitle = TextView(this).apply {
                text = "色板"
                setTypeface(typeface, Typeface.BOLD)
                setTextColor(Color.parseColor("#2E241D"))
            }
            root.addView(paletteTitle)

            val scroll = HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
            }
            val chips = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
            }
            paletteChipsRow = chips
            palette.forEach { color ->
                chips.addView(createColorChip(color, current, canvas))
            }
            scroll.addView(chips)
            root.addView(space(8))
            root.addView(scroll)
        }
        return root
    }

    private lateinit var canvas: PigmentCanvasView

    private fun createColorChip(color: Int, current: TextView, canvas: PigmentCanvasView): View {
        return FrameLayout(this).apply {
            val lp = LinearLayout.LayoutParams(dp(44), dp(44))
            lp.marginEnd = dp(10)
            layoutParams = lp
            background = GradientDrawable().apply {
                cornerRadius = dp(14).toFloat()
                setColor(color)
                setStroke(dp(1), Color.WHITE)
            }
            setOnClickListener {
                currentColor = color
                refreshCurrentColorUi()
                canvas.invalidate()
            }
            setOnLongClickListener {
                if (palette.size > 1) {
                    palette.remove(color)
                    (parent as? ViewGroup)?.removeView(this)
                }
                true
            }
        }
    }

    private fun enterPickerMode() {
        hidePanel()
        if (!screenshot.captureInitialized) {
            pendingPickerAfterPermission = true
            onScreenshotPermissionNeeded?.invoke()
            return
        }
        captureFreshFrameAndShowPicker()
    }

    fun setMediaProjection(mediaProjection: MediaProjection?) {
        this.mediaProjection = mediaProjection
        if (mediaProjection != null) {
            screenshot.initPersistentCapture(mediaProjection)
            if (pendingPickerAfterPermission) {
                pendingPickerAfterPermission = false
                mainHandler.post { captureFreshFrameAndShowPicker() }
            }
        }
    }

    fun handleScreenshotPermissionDenied() {
        if (!pendingPickerAfterPermission) return
        pendingPickerAfterPermission = false
        mainHandler.post {
            hidePickerOverlay()
            showPanel()
        }
    }

    private fun showPickerOverlay(bitmap: Bitmap?) {
        if (pickerView != null) return
        pickerParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        )
        pickerView = PigmentPickerOverlay(this, bitmap) { color ->
            currentColor = color
            if (!palette.contains(color)) {
                palette.add(0, color)
                prependPaletteChip(color)
            }
            refreshCurrentColorUi()
            hidePickerOverlay()
            showPanel()
        }.apply {
            onCancel = {
                hidePickerOverlay()
                showPanel()
            }
        }
        windowManager?.addView(pickerView, pickerParams)
    }

    private fun captureFreshFrameAndShowPicker() {
        mainHandler.postDelayed({
            screenshot.discardPendingFrames()
            screenshot.awaitNextFrame { bitmap ->
                mainHandler.post {
                    if (bitmap != null) {
                        showPickerOverlay(bitmap)
                    } else {
                        showPickerOverlay(null)
                        Toast.makeText(this, "取色帧获取失败，已使用备用取色层", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }, pickerCaptureDelayMs)
    }

    private fun hidePickerOverlay() {
        pickerView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
        }
        pickerView = null
        pickerParams = null
    }

    fun isShowing(): Boolean = bubbleView != null || panelView != null || pickerView != null

    private fun removeBubble() {
        bubbleView?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
        }
        bubbleView = null
        bubbleParams = null
    }

    private fun removeAllViews() {
        hidePanel()
        hidePickerOverlay()
        removeBubble()
    }

    private fun safeUpdate(view: View?, params: WindowManager.LayoutParams?) {
        if (view == null || params == null) return
        try {
            windowManager?.updateViewLayout(view, params)
        } catch (_: Exception) {
        }
    }

    private fun panelButton(label: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = label
            isAllCaps = false
            setOnClickListener { onClick() }
        }
    }

    private fun simpleSeek(onChange: (Float) -> Unit): SeekBar.OnSeekBarChangeListener {
        return object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                onChange(progress.toFloat())
            }
            override fun onStartTrackingTouch(seekBar: SeekBar?) {}
            override fun onStopTrackingTouch(seekBar: SeekBar?) {}
        }
    }

    private fun space(dp: Int): View = Space(this).apply {
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            this@PigmentFloatingManager.dp(dp),
        )
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun currentColorText(): String = "当前 ${hex(currentColor)}"

    private fun refreshCurrentColorUi() {
        bubbleView?.background?.invalidateSelf()
        currentColorLabel?.text = currentColorText()
    }

    private fun prependPaletteChip(color: Int) {
        val current = currentColorLabel ?: return
        val canvasView = if (::canvas.isInitialized) canvas else return
        val chips = paletteChipsRow ?: return
        chips.addView(createColorChip(color, current, canvasView), 0)
    }

    private fun panelHeightForState(): Int = if (panelCollapsed) dp(360) else dp(560)

    private fun togglePanelCollapsed() {
        panelCollapsed = !panelCollapsed
        rebuildPanelForState()
    }

    private fun rebuildPanelForState() {
        val existingView = panelView ?: return
        val params = panelParams ?: return
        val metrics = resources.displayMetrics
        val targetHeight = panelHeightForState()
        val currentBottom = params.y + params.height
        params.height = targetHeight
        params.y = currentBottom.coerceAtLeast(dp(96) + targetHeight) - targetHeight
        params.y = params.y.coerceIn(dp(96), metrics.heightPixels - targetHeight - dp(12))

        val parent = existingView.parent
        if (parent != null) {
            try {
                windowManager?.removeView(existingView)
            } catch (_: Exception) {
            }
        }

        currentColorLabel = null
        paletteChipsRow = null
        panelView = createPanelView()
        windowManager?.addView(panelView, params)
    }

    private fun undoStroke() {
        if (strokes.isEmpty() || !::canvas.isInitialized) return
        val lastIndex = strokes.lastIndex
        if (lastIndex < 0) return
        redo.add(strokes.removeAt(lastIndex))
        canvas.postInvalidateOnAnimation()
    }

    private fun redoStroke() {
        if (redo.isEmpty() || !::canvas.isInitialized) return
        val lastIndex = redo.lastIndex
        if (lastIndex < 0) return
        strokes.add(redo.removeAt(lastIndex))
        canvas.postInvalidateOnAnimation()
    }

    private fun clearCanvas() {
        if (!::canvas.isInitialized) return
        strokes.clear()
        redo.clear()
        canvas.postInvalidateOnAnimation()
    }

    private fun pigmentMix(a: Int, b: Int, t: Float): Int {
        val base = android.animation.ArgbEvaluator().evaluate(t, a, b) as Int
        val hsv = FloatArray(3)
        Color.colorToHSV(base, hsv)
        hsv[1] = (hsv[1] * (0.92f + kotlin.math.sin(t * Math.PI).toFloat() * 0.08f)).coerceIn(0f, 1f)
        hsv[2] = (hsv[2] - kotlin.math.sin(t * Math.PI).toFloat() * 0.05f).coerceIn(0f, 1f)
        return Color.HSVToColor(hsv)
    }

    private fun bestOnColor(color: Int): Int {
        val darkness = 1 - (0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color)) / 255
        return if (darkness < 0.45) Color.BLACK else Color.WHITE
    }

    private fun hex(color: Int): String {
        return String.format("#%02X%02X%02X", Color.red(color), Color.green(color), Color.blue(color))
    }

    inner class PigmentCanvasView(context: Context) : View(context) {
        var onColorConsumed: ((Int) -> Unit)? = null
        private var active = mutableListOf<PaintStamp>()
        private var lastTouchX = 0f
        private var lastTouchY = 0f
        private val blurPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val corePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val bridgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeCap = Paint.Cap.ROUND
        }

        init {
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(Color.WHITE)
                setStroke(dp(1), Color.parseColor("#EDEDED"))
            }
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    active = mutableListOf(createStamp(event.x, event.y))
                    lastTouchX = event.x
                    lastTouchY = event.y
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    appendInterpolatedStamps(lastTouchX, lastTouchY, event.x, event.y)
                    lastTouchX = event.x
                    lastTouchY = event.y
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (active.isNotEmpty()) {
                        strokes.add(PaintStroke(active.toList()))
                        redo.clear()
                        active = mutableListOf()
                        invalidate()
                    }
                    return true
                }
            }
            return super.onTouchEvent(event)
        }

        private fun appendInterpolatedStamps(fromX: Float, fromY: Float, toX: Float, toY: Float) {
            val dx = toX - fromX
            val dy = toY - fromY
            val distance = kotlin.math.sqrt(dx * dx + dy * dy)
            if (distance <= 0f) {
                active.add(createStamp(toX, toY))
                return
            }

            val sampled = sampleExistingColor(toX, toY)
            val mixed = if (sampled == null) currentColor else pigmentMix(currentColor, sampled, wetness)
            onColorConsumed?.invoke(mixed)

            val spacing = max(brushRadius * 0.48f, 4.5f)
            val steps = max(1, kotlin.math.ceil(distance / spacing).toInt())
            for (step in 1..steps) {
                val t = step / steps.toFloat()
                val x = fromX + dx * t
                val y = fromY + dy * t
                active.add(PaintStamp(x, y, brushRadius, mixed))
            }
        }

        private fun createStamp(x: Float, y: Float): PaintStamp {
            val sampled = sampleExistingColor(x, y)
            val mixed = if (sampled == null) currentColor else pigmentMix(currentColor, sampled, wetness)
            onColorConsumed?.invoke(mixed)
            return PaintStamp(x, y, brushRadius, mixed)
        }

        private fun sampleExistingColor(x: Float, y: Float): Int? {
            val all = strokes.flatMap { it.stamps }
            var best: PaintStamp? = null
            var bestDistance = Float.MAX_VALUE
            for (stamp in all.asReversed()) {
                val dx = stamp.x - x
                val dy = stamp.y - y
                val d = kotlin.math.sqrt(dx * dx + dy * dy)
                if (d <= stamp.radius * 1.4f && d < bestDistance) {
                    bestDistance = d
                    best = stamp
                }
            }
            return best?.color
        }

        override fun onDraw(canvasRef: Canvas) {
            super.onDraw(canvasRef)
            for (stroke in strokes) drawStroke(canvasRef, stroke)
            if (active.isNotEmpty()) drawStroke(canvasRef, PaintStroke(active))
        }

        private fun drawStroke(canvasRef: Canvas, stroke: PaintStroke) {
            val stamps = stroke.stamps
            stamps.forEachIndexed { index, stamp ->
                blurPaint.color = stamp.color
                blurPaint.alpha = 224
                blurPaint.maskFilter = BlurMaskFilter(4.2f, BlurMaskFilter.Blur.NORMAL)
                canvasRef.drawCircle(stamp.x, stamp.y, stamp.radius, blurPaint)

                corePaint.color = stamp.color
                canvasRef.drawCircle(stamp.x, stamp.y, stamp.radius * 0.9f, corePaint)

                if (index > 0) {
                    val prev = stamps[index - 1]
                    bridgePaint.color = pigmentMix(prev.color, stamp.color, 0.5f)
                    bridgePaint.alpha = 180
                    bridgePaint.strokeWidth = stamp.radius * 1.65f
                    bridgePaint.maskFilter = BlurMaskFilter(4f, BlurMaskFilter.Blur.NORMAL)
                    canvasRef.drawLine(prev.x, prev.y, stamp.x, stamp.y, bridgePaint)
                }
            }
        }
    }
}

private class PigmentPickerOverlay(
    context: Context,
    private val bitmap: Bitmap?,
    private val onPicked: (Int) -> Unit,
) : FrameLayout(context) {
    var onCancel: (() -> Unit)? = null
    private var pointerX = 220f
    private var pointerY = 460f
    private var hoverColor = Color.parseColor("#0D1B44")
    private var rawPointerX = 220f
    private var rawPointerY = 460f
    private var sampleNormalizedX = 0.5f
    private var sampleNormalizedY = 0.5f

    init {
        setWillNotDraw(false)
        setBackgroundColor(Color.argb(120, 0, 0, 0))
        setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                    pointerX = event.x
                    pointerY = event.y
                    rawPointerX = event.rawX
                    rawPointerY = event.rawY
                    updateSamplePoint(pointerX, pointerY, rawPointerX, rawPointerY)
                    hoverColor = sampleColor()
                    invalidate()
                    true
                }
                MotionEvent.ACTION_UP -> {
                    onPicked(hoverColor)
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    onCancel?.invoke()
                    true
                }
                else -> false
            }
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val loupeCx = pointerX
        val density = context.resources.displayMetrics.density
        val loupeCy = (pointerY - density * 160f)
            .coerceAtLeast(density * 96f)
        val radius = density * 82f
        val sampleScreenX = sampleNormalizedX * width
        val sampleScreenY = sampleNormalizedY * height

        drawSampleMarker(canvas, sampleScreenX, sampleScreenY)

        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = createLoupeShader(loupeCx, loupeCy) }
        canvas.drawCircle(loupeCx, loupeCy, radius, paint)

        val tintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(46, 255, 255, 255)
        }
        canvas.drawCircle(loupeCx, loupeCy, radius, tintPaint)

        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = density * 2
            color = Color.WHITE
        }
        canvas.drawCircle(loupeCx, loupeCy, radius, border)

        val cross = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            strokeWidth = density * 1.5f
        }
        canvas.drawLine(loupeCx - 24f, loupeCy, loupeCx + 24f, loupeCy, cross)
        canvas.drawLine(loupeCx, loupeCy - 24f, loupeCx, loupeCy + 24f, cross)

        val pillRect = RectF(pointerX - 118f, pointerY + 26f, pointerX + 118f, pointerY + 80f)
        val pillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        canvas.drawRoundRect(pillRect, 24f, 24f, pillPaint)
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#2E241D")
            textSize = context.resources.displayMetrics.scaledDensity * 14f
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        }
        canvas.drawText(
            String.format("#%02X%02X%02X", Color.red(hoverColor), Color.green(hoverColor), Color.blue(hoverColor)),
            pillRect.centerX(),
            pillRect.centerY() - 1f,
            text,
        )
        val caption = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#7A6A5D")
            textSize = context.resources.displayMetrics.scaledDensity * 10f
            textAlign = Paint.Align.CENTER
        }
        canvas.drawText("采样点", pillRect.centerX(), pillRect.bottom - 10f, caption)
    }

    private fun updateSamplePoint(x: Float, y: Float, rawX: Float, rawY: Float) {
        val viewWidth = width.takeIf { value -> value > 0 } ?: context.resources.displayMetrics.widthPixels
        val viewHeight = height.takeIf { value -> value > 0 } ?: context.resources.displayMetrics.heightPixels
        sampleNormalizedX = ((if (rawX > 0f) rawX else x) / viewWidth.toFloat()).coerceIn(0f, 1f)
        sampleNormalizedY = ((if (rawY > 0f) rawY else y) / viewHeight.toFloat()).coerceIn(0f, 1f)
    }

    private fun sampleColor(): Int {
        bitmap?.let {
            val bx = (sampleNormalizedX * it.width).toInt().coerceIn(0, it.width - 1)
            val by = (sampleNormalizedY * it.height).toInt().coerceIn(0, it.height - 1)
            return it.getPixel(bx, by)
        }
        return android.animation.ArgbEvaluator().evaluate(
            sampleNormalizedX,
            Color.parseColor("#0D1B44"),
            android.animation.ArgbEvaluator().evaluate(
                sampleNormalizedY,
                Color.parseColor("#FFD000"),
                Color.parseColor("#E12301"),
            ) as Int,
        ) as Int
    }

    private fun createLoupeShader(loupeCx: Float, loupeCy: Float): Shader {
        bitmap?.let {
            val shader = BitmapShader(it, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            val scale = 5f
            val bitmapX = sampleNormalizedX * it.width
            val bitmapY = sampleNormalizedY * it.height
            val matrix = Matrix().apply {
                postScale(scale, scale)
                postTranslate(loupeCx - bitmapX * scale, loupeCy - bitmapY * scale)
            }
            shader.setLocalMatrix(matrix)
            return shader
        }
        return RadialGradient(
            loupeCx,
            loupeCy,
            context.resources.displayMetrics.density * 56f,
            lighten(hoverColor, 0.2f),
            darken(hoverColor, 0.08f),
            Shader.TileMode.CLAMP,
        )
    }

    private fun drawSampleMarker(canvas: Canvas, x: Float, y: Float) {
        val ringOuter = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = context.resources.displayMetrics.density * 2f
            color = Color.WHITE
        }
        val ringInner = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = context.resources.displayMetrics.density
            color = Color.parseColor("#2E241D")
        }
        val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = hoverColor }
        canvas.drawCircle(x, y, context.resources.displayMetrics.density * 12f, ringOuter)
        canvas.drawCircle(x, y, context.resources.displayMetrics.density * 8f, ringInner)
        canvas.drawCircle(x, y, context.resources.displayMetrics.density * 4f, dot)
    }

    private fun lighten(color: Int, t: Float): Int {
        return android.animation.ArgbEvaluator().evaluate(t, color, Color.WHITE) as Int
    }

    private fun darken(color: Int, t: Float): Int {
        return android.animation.ArgbEvaluator().evaluate(t, color, Color.BLACK) as Int
    }
}

private data class PaintStroke(val stamps: List<PaintStamp>)
private data class PaintStamp(val x: Float, val y: Float, val radius: Float, val color: Int)

private class BubbleDrawable(private val colorProvider: () -> Int) : android.graphics.drawable.Drawable() {
    override fun draw(canvas: Canvas) {
        val color = colorProvider()
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            alpha = 90
            maskFilter = BlurMaskFilter(18f, BlurMaskFilter.Blur.NORMAL)
        }
        val rect = bounds
        val cx = rect.exactCenterX()
        val cy = rect.exactCenterY()
        canvas.drawCircle(cx, cy + 8f, rect.width() / 2f - 2f, shadow)
        canvas.drawCircle(cx, cy, rect.width() / 2f - 2f, paint)
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.4f
            this.color = Color.WHITE
            alpha = 180
        }
        canvas.drawCircle(cx, cy, rect.width() / 2f - 2f, border)
    }
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

private class PanelDrawable : android.graphics.drawable.Drawable() {
    override fun draw(canvas: Canvas) {
        val rect = RectF(bounds)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.argb(238, 255, 255, 255)
        }
        canvas.drawRoundRect(rect, 30f, 30f, paint)
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1f
            color = Color.argb(170, 255, 255, 255)
        }
        canvas.drawRoundRect(rect, 30f, 30f, border)
    }
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
