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
import io.github.xiaodouzi.fr.native.liquid.LiquidGlassChannel
import io.github.xiaodouzi.fr.native.overlay.FloatingChannel
import io.github.xiaodouzi.fr.native.overlay.FloatingWindowManager
import io.github.xiaodouzi.fr.native.system.SystemChannel
import io.github.xiaodouzi.fr.native.volume.VolumeChannel
import io.github.xiaodouzi.fr.native.widget.WidgetChannel

class MainActivity : FlutterActivity() {
    private lateinit var widgetChannel: WidgetChannel
    private lateinit var clockChannel: ClockChannel
    private lateinit var systemChannel: SystemChannel
    private lateinit var floatingChannel: FloatingChannel
    private lateinit var volumeChannel: VolumeChannel

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var regionCaptureReceiver: BroadcastReceiver? = null
    private var aiQuestionReceiver: BroadcastReceiver? = null
    private val SCREEN_CAPTURE_REQUEST_CODE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

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

        // Liquid Glass Channel
        LiquidGlassChannel.register(messenger)
    }

    private fun notifyFlutter(method: String, args: Any?) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            io.flutter.plugin.common.MethodChannel(messenger, FloatingChannel.NAME)
                .invokeMethod(method, args)
        }
    }

    private fun requestScreenCapturePermission() {
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = mediaProjectionManager?.createScreenCaptureIntent()
        intent?.let { startActivityForResult(it, SCREEN_CAPTURE_REQUEST_CODE) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREEN_CAPTURE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                FloatingWindowManager.getInstance()?.promoteToForeground()
                val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val mediaProjection = mpManager.getMediaProjection(resultCode, data!!)
                FloatingWindowManager.getInstance()?.setMediaProjection(mediaProjection)
                floatingChannel.notifyPermissionGranted()
            } else {
                floatingChannel.notifyPermissionDenied()
            }
        }
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
