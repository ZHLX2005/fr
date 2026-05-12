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
import androidx.core.graphics.ColorUtils
import io.github.xiaodouzi.fr.native.overlay.FloatingWindowScreenshot
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class PigmentFloatingManager : Service() {
    private val panelWhite = Color.parseColor("#FFFFFF")
    private val panelWhiteSoft = Color.parseColor("#FFFFFF")
    private val panelWhiteMuted = Color.parseColor("#FFFFFF")
    private val panelBorder = Color.parseColor("#E7E7E3")
    private val panelDivider = Color.parseColor("#F0F0ED")
    private val panelTextPrimary = Color.parseColor("#111111")
    private val panelTextSecondary = Color.parseColor("#6B6B6B")
    private val panelAccent = Color.parseColor("#1F7AFF")

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
        view.elevation = dp(10).toFloat()

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
            setPadding(dp(14), dp(14), dp(14), dp(14))
            background = PanelDrawable()
            elevation = dp(16).toFloat()
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

        val colorIndicator = createColorIndicator()
        val titleGroup = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val titleRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        titleRow.addView(colorIndicator)
        titleRow.addView(TextView(this).apply {
            text = "Pigment 画板"
            setTextColor(panelTextPrimary)
            textSize = 16f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setPadding(dp(10), 0, 0, 0)
        })
        currentColorLabel = TextView(this).apply {
            text = currentColorText()
            setTextColor(panelTextSecondary)
            textSize = 12f
            setPadding(dp(2), dp(4), 0, 0)
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.NORMAL)
        }
        titleGroup.addView(titleRow)
        titleGroup.addView(currentColorLabel)
        header.addView(titleGroup, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        val collapseToggle = createIconButton(
            if (panelCollapsed) android.R.drawable.arrow_down_float else android.R.drawable.arrow_up_float
        ) { togglePanelCollapsed() }
        header.addView(collapseToggle)

        val close = createIconButton(android.R.drawable.ic_menu_close_clear_cancel) { hidePanel() }
        header.addView(close)
        root.addView(header)

        root.addView(space(8))

        val tools = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val pickerBtn = createIconButton(android.R.drawable.ic_menu_edit) { enterPickerMode() }
        tools.addView(pickerBtn)
        if (!panelCollapsed) {
            val undoBtn = createIconTextButton("↶") { undoStroke() }
            val redoBtn = createIconTextButton("↷") { redoStroke() }
            val clearBtn = createIconTextButton("×") { clearCanvas() }
            tools.addView(undoBtn)
            tools.addView(redoBtn)
            tools.addView(clearBtn)
        }
        tools.addView(createSpace(), LinearLayout.LayoutParams(0, 1, 1f))
        root.addView(tools)

        if (!panelCollapsed) {
            root.addView(space(8))

            val brushRow = createSliderRow("●") { value ->
                brushRadius = 8f + value * 26f
            }
            root.addView(brushRow)

            root.addView(space(4))

            val wetRow = createSliderRow("💧") { value ->
                wetness = value
            }
            root.addView(wetRow)
        }

        root.addView(space(8))
        val canvas = PigmentCanvasView(this).apply {
            minimumHeight = dp(180)
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
            root.addView(space(8))

            val scroll = HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
            }
            val chips = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
            }
            paletteChipsRow = chips
            palette.forEach { color ->
                chips.addView(createColorChip(color))
            }
            scroll.addView(chips)
            root.addView(scroll)
        }
        return root
    }

    private lateinit var canvas: PigmentCanvasView

    private fun createColorIndicator(): View {
        return FrameLayout(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
            background = object : android.graphics.drawable.Drawable() {
                override fun draw(canvas: android.graphics.Canvas) {
                    val density = resources.displayMetrics.density
                    val outer = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = panelWhiteSoft
                        style = Paint.Style.FILL
                    }
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = currentColor
                        style = Paint.Style.FILL
                    }
                    val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = panelBorder
                        style = Paint.Style.STROKE
                        strokeWidth = density
                    }
                    val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                        color = ColorUtils.setAlphaComponent(Color.BLACK, 16)
                        maskFilter = BlurMaskFilter(10f * density, BlurMaskFilter.Blur.NORMAL)
                    }
                    val cx = bounds.exactCenterX()
                    val cy = bounds.exactCenterY()
                    val radius = bounds.width() / 2f - 2f * density
                    canvas.drawCircle(cx, cy + 2f * density, radius - density, shadow)
                    canvas.drawCircle(cx, cy, radius, outer)
                    canvas.drawCircle(cx, cy, radius * 0.62f, paint)
                    canvas.drawCircle(cx, cy, radius, border)
                }
                override fun setAlpha(alpha: Int) {}
                override fun setColorFilter(colorFilter: ColorFilter?) {}
                override fun getOpacity(): Int = android.graphics.PixelFormat.TRANSLUCENT
            }
        }
    }

    private fun createIconButton(iconRes: Int, onClick: () -> Unit): View {
        return ImageButton(this).apply {
            setImageResource(iconRes)
            background = roundedRectDrawable(panelWhiteMuted, panelBorder, 18f)
            setColorFilter(panelTextPrimary)
            setPadding(dp(8), dp(8), dp(8), dp(8))
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(40)).apply {
                marginStart = dp(8)
            }
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            elevation = dp(1).toFloat()
            setOnClickListener { onClick() }
        }
    }

    private fun createIconTextButton(text: String, onClick: () -> Unit): View {
        return TextView(this).apply {
            this.text = text
            textSize = 18f
            gravity = Gravity.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setTextColor(panelTextPrimary)
            background = roundedRectDrawable(panelWhiteMuted, panelBorder, 18f)
            setPadding(dp(12), dp(8), dp(12), dp(8))
            layoutParams = LinearLayout.LayoutParams(dp(42), dp(40)).apply {
                marginStart = dp(8)
            }
            elevation = dp(1).toFloat()
            setOnClickListener { onClick() }
        }
    }

    private fun createSpace(): View {
        return Space(this)
    }

    private fun createSliderRow(icon: String, onValueChange: (Float) -> Unit): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = roundedRectDrawable(panelWhiteSoft, panelDivider, 20f)
        }

        val iconView = TextView(this).apply {
            text = icon
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(panelTextPrimary)
            setPadding(0, 0, dp(10), 0)
        }
        row.addView(iconView)

        val seekBar = SeekBar(this).apply {
            max = 100
            progress = 50
            setPadding(0, 0, 0, 0)
            progressTintList = android.content.res.ColorStateList.valueOf(panelAccent)
            progressBackgroundTintList = android.content.res.ColorStateList.valueOf(panelBorder)
            thumbTintList = android.content.res.ColorStateList.valueOf(panelAccent)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(seekBar: SeekBar?, progress: Int, fromUser: Boolean) {
                    if (fromUser) onValueChange(progress / 100f)
                }
                override fun onStartTrackingTouch(seekBar: SeekBar?) {}
                override fun onStopTrackingTouch(seekBar: SeekBar?) {}
            })
        }
        row.addView(seekBar, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))

        return row
    }

    private fun createColorChip(color: Int): View {
        return FrameLayout(this).apply {
            val lp = LinearLayout.LayoutParams(dp(40), dp(40))
            lp.marginEnd = dp(8)
            layoutParams = lp
            background = GradientDrawable().apply {
                cornerRadius = dp(20).toFloat()
                setColor(color)
                setStroke(dp(1), if (isLightColor(color)) panelBorder else ColorUtils.setAlphaComponent(Color.WHITE, 180))
            }
            elevation = dp(1).toFloat()
            setOnClickListener {
                currentColor = color
                refreshCurrentColorUi()
                if (::canvas.isInitialized) canvas.invalidate()
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
        (bubbleView as? ViewGroup)?.getChildAt(0)?.let { icon ->
            if (icon is ImageView) {
                icon.setColorFilter(bestOnColor(currentColor))
            }
        }
        currentColorLabel?.text = currentColorText()
    }

    private fun prependPaletteChip(color: Int) {
        val chips = paletteChipsRow ?: return
        chips.addView(createColorChip(color), 0)
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
        canvas.invalidateCache()
        canvas.postInvalidateOnAnimation()
    }

    private fun redoStroke() {
        if (redo.isEmpty() || !::canvas.isInitialized) return
        val lastIndex = redo.lastIndex
        if (lastIndex < 0) return
        strokes.add(redo.removeAt(lastIndex))
        canvas.invalidateCache()
        canvas.postInvalidateOnAnimation()
    }

    private fun clearCanvas() {
        if (!::canvas.isInitialized) return
        strokes.clear()
        redo.clear()
        canvas.invalidateCache()
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

    private fun roundedRectDrawable(fillColor: Int, strokeColor: Int, radiusDp: Float): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(radiusDp.toInt()).toFloat()
            setColor(fillColor)
            setStroke(dp(1), strokeColor)
        }
    }

    private fun isLightColor(color: Int): Boolean {
        return ColorUtils.calculateLuminance(color) > 0.82
    }

    inner class PigmentCanvasView(context: Context) : View(context) {
        var onColorConsumed: ((Int) -> Unit)? = null
        private var active = mutableListOf<PaintStamp>()
        private var lastTouchX = 0f
        private var lastTouchY = 0f
        private var lastTouchTime = 0L
        private val blurPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val corePaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val bridgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            strokeCap = Paint.Cap.ROUND
        }

        private var strokeCache: Bitmap? = null
        private var cacheCanvas: Canvas? = null
        private val dirtyRect = Rect()
        private var cacheValid = false

        init {
            background = GradientDrawable().apply {
                cornerRadius = dp(24).toFloat()
                setColor(panelWhite)
                setStroke(dp(1), panelBorder)
            }
        }

        private fun ensureCache() {
            if (strokeCache == null && width > 0 && height > 0) {
                strokeCache = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                cacheCanvas = Canvas(strokeCache!!)
                cacheCanvas?.drawColor(Color.TRANSPARENT)
            }
        }

        internal fun invalidateCache() {
            cacheValid = false
        }

        private fun rebuildCache() {
            if (cacheValid) return
            ensureCache() ?: return
            val canvas = cacheCanvas ?: return
            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
            for (stroke in strokes) {
                drawStrokeToCache(canvas, stroke)
            }
            cacheValid = true
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            strokeCache?.recycle()
            strokeCache = null
            cacheCanvas = null
            invalidateCache()
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    lastTouchTime = event.eventTime
                    active = mutableListOf(createStamp(event.x, event.y))
                    lastTouchX = event.x
                    lastTouchY = event.y
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val currentTime = event.eventTime
                    appendInterpolatedStamps(lastTouchX, lastTouchY, event.x, event.y, currentTime - lastTouchTime)
                    lastTouchX = event.x
                    lastTouchY = event.y
                    lastTouchTime = currentTime
                    invalidate()
                    return true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    if (active.isNotEmpty()) {
                        val newStroke = PaintStroke(active.toList())
                        strokes.add(newStroke)
                        redo.clear()
                        active = mutableListOf()
                        commitStrokeToCache(newStroke)
                        invalidateCache()
                        invalidate()
                    }
                    return true
                }
            }
            return super.onTouchEvent(event)
        }

        private fun commitStrokeToCache(stroke: PaintStroke) {
            ensureCache() ?: return
            val canvas = cacheCanvas ?: return
            drawStrokeToCache(canvas, stroke)
        }

        private fun appendInterpolatedStamps(fromX: Float, fromY: Float, toX: Float, toY: Float, deltaTimeMs: Long) {
            val dx = toX - fromX
            val dy = toY - fromY
            val distance = kotlin.math.sqrt(dx * dx + dy * dy)
            if (distance <= 0f) {
                active.add(createStamp(toX, toY))
                return
            }

            val velocity = if (deltaTimeMs > 0) distance / max(deltaTimeMs, 1L) * 1000f else 0f
            val velocityFactor = (velocity / 1000f).coerceIn(0f, 1f)

            val dynamicSpacing = max(brushRadius * 0.48f * (1f + velocityFactor * 0.8f), 4.5f)
            val dynamicRadius = brushRadius * (1f - velocityFactor * 0.15f).coerceIn(0.6f, 1f)

            val steps = max(1, kotlin.math.ceil(distance / dynamicSpacing).toInt())

            val sampled = sampleExistingColor(toX, toY)
            val strokeColor = if (sampled == null) currentColor else pigmentMix(currentColor, sampled, wetness)
            onColorConsumed?.invoke(strokeColor)

            for (step in 1..steps) {
                val t = step / steps.toFloat()
                val x = fromX + dx * t
                val y = fromY + dy * t
                active.add(PaintStamp(x, y, dynamicRadius, strokeColor))
            }
        }

        private fun createStamp(x: Float, y: Float): PaintStamp {
            val sampled = sampleExistingColor(x, y)
            val mixed = if (sampled == null) currentColor else pigmentMix(currentColor, sampled, wetness)
            onColorConsumed?.invoke(mixed)
            return PaintStamp(x, y, brushRadius, mixed)
        }

        private fun sampleExistingColor(x: Float, y: Float): Int? {
            var best: PaintStamp? = null
            var bestDistance = Float.MAX_VALUE

            fun checkStamps(stampList: List<PaintStamp>): Boolean {
                for (stamp in stampList.asReversed()) {
                    val dx = stamp.x - x
                    val dy = stamp.y - y
                    val d = kotlin.math.sqrt(dx * dx + dy * dy)
                    if (d <= stamp.radius * 1.4f && d < bestDistance) {
                        bestDistance = d
                        best = stamp
                    }
                }
                return best != null
            }

            val recentStrokes = strokes.takeLast(3)
            for (stroke in recentStrokes.reversed()) {
                if (checkStamps(stroke.stamps)) return best?.color
            }

            return best?.color
        }

        override fun onDraw(canvasRef: Canvas) {
            super.onDraw(canvasRef)
            rebuildCache()
            strokeCache?.let { canvasRef.drawBitmap(it, 0f, 0f, null) }
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

        private fun drawStrokeToCache(canvasRef: Canvas, stroke: PaintStroke) {
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
        setBackgroundColor(Color.argb(84, 255, 255, 255))
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
            color = Color.argb(34, 255, 255, 255)
        }
        canvas.drawCircle(loupeCx, loupeCy, radius, tintPaint)

        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = density * 2
            color = Color.parseColor("#F5F5F2")
        }
        canvas.drawCircle(loupeCx, loupeCy, radius, border)

        val cross = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FCFCFA")
            strokeWidth = density * 1.5f
        }
        canvas.drawLine(loupeCx - 24f, loupeCy, loupeCx + 24f, loupeCy, cross)
        canvas.drawLine(loupeCx, loupeCy - 24f, loupeCx, loupeCy + 24f, cross)

        val pillRect = RectF(pointerX - 124f, pointerY + 26f, pointerX + 124f, pointerY + 84f)
        val pillShadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ColorUtils.setAlphaComponent(Color.BLACK, 18)
            maskFilter = BlurMaskFilter(density * 14f, BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawRoundRect(
            RectF(pillRect.left, pillRect.top + density * 3f, pillRect.right, pillRect.bottom + density * 3f),
            28f,
            28f,
            pillShadow,
        )
        val pillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#FFFFFF") }
        canvas.drawRoundRect(pillRect, 24f, 24f, pillPaint)
        val pillBorder = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = density
            color = Color.parseColor("#E9E7E2")
        }
        canvas.drawRoundRect(pillRect, 24f, 24f, pillBorder)
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#111111")
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
            color = Color.parseColor("#6B6B6B")
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
            color = Color.parseColor("#B9B5AE")
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
        val outer = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = Color.parseColor("#FFFFFF") }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = ColorUtils.setAlphaComponent(Color.BLACK, 22)
            maskFilter = BlurMaskFilter(20f, BlurMaskFilter.Blur.NORMAL)
        }
        val rect = bounds
        val cx = rect.exactCenterX()
        val cy = rect.exactCenterY()
        val radius = rect.width() / 2f - 2f
        canvas.drawCircle(cx, cy + 6f, radius, shadow)
        canvas.drawCircle(cx, cy, radius, outer)
        canvas.drawCircle(cx, cy, radius * 0.72f, paint)
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.4f
            this.color = Color.parseColor("#E9E7E2")
        }
        canvas.drawCircle(cx, cy, radius, border)
    }
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}

private class PanelDrawable : android.graphics.drawable.Drawable() {
    override fun draw(canvas: Canvas) {
        val rect = RectF(bounds)
        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ColorUtils.setAlphaComponent(Color.BLACK, 12)
            maskFilter = BlurMaskFilter(28f, BlurMaskFilter.Blur.NORMAL)
        }
        canvas.drawRoundRect(RectF(rect.left, rect.top + 8f, rect.right, rect.bottom + 8f), 32f, 32f, shadow)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#FFFFFF")
        }
        canvas.drawRoundRect(rect, 32f, 32f, paint)
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1f
            color = Color.parseColor("#E7E7E3")
        }
        canvas.drawRoundRect(rect, 32f, 32f, border)
    }
    override fun setAlpha(alpha: Int) {}
    override fun setColorFilter(colorFilter: ColorFilter?) {}
    override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
}
