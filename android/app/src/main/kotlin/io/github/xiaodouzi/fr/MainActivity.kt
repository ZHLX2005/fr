package io.github.xiaodouzi.fr

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.projection.MediaProjectionManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.github.xiaodouzi.fr.native.calendar.CalendarChannel
import io.github.xiaodouzi.fr.native.clock.ClockChannel
import io.github.xiaodouzi.fr.native.crash.CrashLogChannel
import io.github.xiaodouzi.fr.native.crash.CrashLogHandler
import io.github.xiaodouzi.fr.native.overlay.FloatingChannel
import io.github.xiaodouzi.fr.native.overlay.FloatingWindowManager
import io.github.xiaodouzi.fr.native.pigment.PigmentFloatingManager
import io.github.xiaodouzi.fr.native.system.SystemChannel
import io.github.xiaodouzi.fr.native.novel.NovelVolumeKeyChannel
import io.github.xiaodouzi.fr.native.volume.VolumeChannel
import io.github.xiaodouzi.fr.native.widget.WidgetChannel

class MainActivity : FlutterActivity() {
    private lateinit var widgetChannel: WidgetChannel
    private lateinit var clockChannel: ClockChannel
    private lateinit var calendarChannel: CalendarChannel
    private lateinit var systemChannel: SystemChannel
    private lateinit var floatingChannel: FloatingChannel
    private lateinit var volumeChannel: VolumeChannel
    private lateinit var novelVolumeKeyChannel: NovelVolumeKeyChannel

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var regionCaptureReceiver: BroadcastReceiver? = null
    private var aiQuestionReceiver: BroadcastReceiver? = null
    private val OVERLAY_SCREEN_CAPTURE_REQUEST_CODE = 1001
    private val PIGMENT_SCREEN_CAPTURE_REQUEST_CODE = 1002
    private var pendingPermissionService: String? = null

    // 冷启动深链是否已兜底处理过。
    // 避免 widget 打开页面后页面被重复 push 导致返回手势多重折叠 / 页面堆叠：
    // - warm start：深链由 onNewIntent 处理（每次 widget 点击回调一次）
    // - cold start：onNewIntent 不回调，深链只能在首次 onResume 兜底一次
    // - 普通前后台切换：不得重复处理，杜绝每次回到前台都再 push 一层
    private var hasHandledInitialIntent = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Crash Log
        CrashLogHandler.init(this)
        CrashLogChannel(messenger, this).setMethodCallHandler()

        // Widget Channel
        widgetChannel = WidgetChannel(messenger).apply {
            onNavigateToLab = { navigateToLab() }
            onNavigateToTimetable = { navigateToTimetable() }
        }

        // Clock Channel
        clockChannel = ClockChannel(messenger, this)

        // Calendar Channel
        calendarChannel = CalendarChannel(messenger, this)

        // System Channel
        systemChannel = SystemChannel(messenger, this)

        // Floating Channel
        floatingChannel = FloatingChannel(messenger, this).apply {
            setMethodCallHandler()
            onScreenshotPermissionGranted = { notifyFlutter("onScreenshotPermissionGranted", null) }
            onScreenshotPermissionDenied = { notifyFlutter("onScreenshotPermissionDenied", null) }
        }

        // Volume Channel
        volumeChannel = VolumeChannel(messenger, this)

        // Novel Reader Volume Key Channel
        novelVolumeKeyChannel = NovelVolumeKeyChannel(messenger)
    }

    private fun notifyFlutter(method: String, args: Any?) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            io.flutter.plugin.common.MethodChannel(messenger, FloatingChannel.NAME)
                .invokeMethod(method, args)
        }
    }

    private fun requestScreenCapturePermission(service: String) {
        pendingPermissionService = service
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = mediaProjectionManager?.createScreenCaptureIntent()
        val requestCode = when (service) {
            "pigment" -> PIGMENT_SCREEN_CAPTURE_REQUEST_CODE
            else -> OVERLAY_SCREEN_CAPTURE_REQUEST_CODE
        }
        intent?.let { startActivityForResult(it, requestCode) }
    }

    init {
        FloatingWindowManager.onScreenshotPermissionNeeded = {
            runOnUiThread { requestScreenCapturePermission("overlay") }
        }
        PigmentFloatingManager.onScreenshotPermissionNeeded = {
            runOnUiThread { requestScreenCapturePermission("pigment") }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            OVERLAY_SCREEN_CAPTURE_REQUEST_CODE -> handleScreenCaptureResult(resultCode, data, "overlay")
            PIGMENT_SCREEN_CAPTURE_REQUEST_CODE -> handleScreenCaptureResult(resultCode, data, "pigment")
        }
    }

    private fun handleScreenCaptureResult(resultCode: Int, data: Intent?, service: String) {
        if (resultCode == Activity.RESULT_OK && data != null) {
            try {
                when (service) {
                    "overlay" -> FloatingWindowManager.getInstance()?.promoteToForeground()
                    "pigment" -> PigmentFloatingManager.getInstance()?.promoteToForeground()
                }

                val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val mediaProjection = mpManager.getMediaProjection(resultCode, data)

                when (service) {
                    "overlay" -> {
                        val floatingManager = FloatingWindowManager.getInstance()
                        // Android 14+ 必须先提升前台服务，再获取 MediaProjection
                        floatingManager?.setMediaProjection(mediaProjection)
                        // 确保 floatingView 已创建（Service 重启后需要重建）
                        if (floatingManager != null && !floatingManager.isFloatingWindowShowing()) {
                            floatingManager.showFloatingWindow()
                        }
                    }
                    "pigment" -> {
                        val pigmentManager = PigmentFloatingManager.getInstance()
                        // Android 14+ 必须先提升前台服务，再设置 MediaProjection
                        pigmentManager?.setMediaProjection(mediaProjection)
                    }
                }
                floatingChannel?.notifyPermissionGranted()
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "getMediaProjection failed: ${e.message}", e)
                when (service) {
                    "overlay" -> {
                        FloatingWindowManager.getInstance()?.resetScreenshotPermissionWaiting()
                    }
                    "pigment" -> {
                        PigmentFloatingManager.getInstance()?.handleScreenshotPermissionDenied()
                    }
                }
                floatingChannel?.notifyPermissionDenied()
            }
        } else {
            // 权限被拒绝，清除持久化状态，重置等待标志
            when (service) {
                "overlay" -> {
                    FloatingWindowManager.setScreenshotPermissionGranted(this, false)
                    FloatingWindowManager.getInstance()?.resetScreenshotPermissionWaiting()
                }
                "pigment" -> {
                    PigmentFloatingManager.getInstance()?.handleScreenshotPermissionDenied()
                }
            }
            floatingChannel?.notifyPermissionDenied()
        }
        pendingPermissionService = null
    }

    override fun onKeyDown(keyCode: Int, event: android.view.KeyEvent?): Boolean {
        if (::novelVolumeKeyChannel.isInitialized &&
            novelVolumeKeyChannel.handleKeyEvent(keyCode, event)
        ) {
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Android 默认不会用新 Intent 覆盖 getIntent()，显式 setIntent
        // 保证后续读取（含可能的二次回调）拿到的都是最新深链。
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        // 仅在冷启动首次进入前台时兜底一次 launching Intent（widget 直接点开 app）。
        // 此后所有普通的前后台切换都跳过，避免反复读取同一份 sticky Intent 而 push 多层页面。
        if (!hasHandledInitialIntent) {
            hasHandledInitialIntent = true
            handleIntent(intent)
        }
        registerRegionCaptureReceiver()
        registerAiQuestionReceiver()
    }

    override fun onDestroy() {
        super.onDestroy()
        regionCaptureReceiver?.let { unregisterReceiver(it) }
        aiQuestionReceiver?.let { unregisterReceiver(it) }
    }

    private fun handleIntent(intent: Intent?) {
        intent?.data?.let { uri ->
            val uriStr = uri.toString()
            if (uriStr == "fr://calendar" || uri.path == "/calendar") {
                widgetChannel.notifyNavigateToCalendar()
            } else if (uriStr == "fr://timetable" || uri.path == "/timetable") {
                widgetChannel.notifyNavigateToTimetable()
            } else if (uriStr == "fr://lab" || uri.path == "/lab") {
                widgetChannel.notifyNavigateToLab()
            }
        }
    }

    private fun navigateToLab() {
        widgetChannel.notifyNavigateToLab()
    }

    private fun navigateToTimetable() {
        widgetChannel.notifyNavigateToTimetable()
    }

    private fun registerRegionCaptureReceiver() {
        if (regionCaptureReceiver != null) return
        regionCaptureReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "io.github.xiaodouzi.fr.REGION_CAPTURED") {
                    val data = intent.getByteArrayExtra("data")
                    data?.let { floatingChannel.notifyRegionCaptured(it) }
                }
            }
        }
        val filter = IntentFilter("io.github.xiaodouzi.fr.REGION_CAPTURED")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Context.RECEIVER_NOT_EXPORTED else 0
        registerReceiver(regionCaptureReceiver, filter, flags)
    }

    private fun registerAiQuestionReceiver() {
        if (aiQuestionReceiver != null) return
        aiQuestionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "io.github.xiaodouzi.fr.AI_QUESTION") {
                    val question = intent.getStringExtra("question") ?: return
                    val imagePath = intent.getStringExtra("image_path") ?: return
                    floatingChannel.notifyAiQuestion(question, imagePath)
                }
            }
        }
        val filter = IntentFilter("io.github.xiaodouzi.fr.AI_QUESTION")
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) Context.RECEIVER_NOT_EXPORTED else 0
        registerReceiver(aiQuestionReceiver, filter, flags)
    }
}
