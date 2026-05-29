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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Crash Log
        CrashLogHandler.init(this)
        CrashLogChannel(messenger, this).setMethodCallHandler()

        // Widget Channel
        widgetChannel = WidgetChannel(messenger).apply {
            onNavigateToLab = { navigateToLab() }
        }

        // Clock Channel
        clockChannel = ClockChannel(messenger, this)

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
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        handleIntent(intent)
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
            if (uri.toString() == "fr://lab" || uri.path == "/lab") {
                widgetChannel.notifyNavigateToLab()
            }
        }
    }

    private fun navigateToLab() {
        widgetChannel.notifyNavigateToLab()
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
