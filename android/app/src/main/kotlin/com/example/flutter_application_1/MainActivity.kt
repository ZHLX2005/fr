package com.example.flutter_application_1

import android.app.Activity
import android.app.AppOpsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.RingtoneManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import com.example.flutter_application_1.native.overlay.FloatingWindowManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flutter_application_1/widget"
    private val CLOCK_CHANNEL = "com.example.flutter_application_1/clock"
    private val SYSTEM_CHANNEL = "com.example.flutter_application_1/system"
    private val FLOATING_CHANNEL = "com.example.flutter_application_1/floating"

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var regionCaptureReceiver: BroadcastReceiver? = null
    private var aiQuestionReceiver: BroadcastReceiver? = null
    private val SCREEN_CAPTURE_REQUEST_CODE = 1001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 设置 MethodChannel 处理来自 Widget 的跳转请求
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "navigateToLab") {
                // 跳转到 Lab 页面
                navigateToLab()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }

        // 时钟相关 MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CLOCK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playNotificationSound" -> {
                    playNotificationSound()
                    result.success(null)
                }
                "vibrate" -> {
                    // Dart 的 int 对应 Java 的 Integer，需要先获取 Int 再转为 Long
                    val duration = (call.argument<Int>("duration") ?: 300).toLong()
                    vibrate(duration)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 系统功能相关 MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsagePermission" -> {
                    val hasPermission = checkUsagePermission()
                    result.success(hasPermission)
                }
                "openUsageSettings" -> {
                    openUsageSettings()
                    result.success(null)
                }
                "queryAppUsage" -> {
                    val usageList = queryAppUsage()
                    result.success(usageList)
                }
                else -> result.notImplemented()
            }
        }

        // 悬浮窗相关 MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FLOATING_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission" -> {
                    // 检查悬浮窗权限
                    val hasPermission = FloatingWindowManager.canDrawOverlays(this)
                    result.success(hasPermission)
                }
                "requestOverlayPermission" -> {
                    // 跳转到悬浮窗权限设置页面
                    val intent = FloatingWindowManager.getOverlaySettingsIntent(this)
                    startActivity(intent)
                    result.success(true)
                }
                "startFloating" -> {
                    // 先检查悬浮窗权限
                    if (!FloatingWindowManager.canDrawOverlays(this)) {
                        // 没有权限，跳转到设置页面
                        val intent = FloatingWindowManager.getOverlaySettingsIntent(this)
                        startActivity(intent)
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    // 启动悬浮窗服务
                    val intent = Intent(this, FloatingWindowManager::class.java).apply {
                        action = FloatingWindowManager.ACTION_START
                    }
                    startForegroundService(intent)

                    // 立即请求截图权限（而非等到截图时再请求）
                    requestScreenCapturePermission()

                    // 设置截图权限请求回调（备用）
                    FloatingWindowManager.onScreenshotPermissionNeeded = {
                        runOnUiThread {
                            requestScreenCapturePermission()
                        }
                    }

                    result.success(true)
                }
                "stopFloating" -> {
                    val intent = Intent(this, FloatingWindowManager::class.java).apply {
                        action = FloatingWindowManager.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "requestScreenshotPermission" -> {
                    // 请求截图权限
                    requestScreenCapturePermission()
                    result.success(true)
                }
                "isFloatingShowing" -> {
                    val manager = FloatingWindowManager.getInstance()
                    result.success(manager?.isFloatingWindowShowing() ?: false)
                }
                "saveScreenshotToGallery" -> {
                    val data = call.arguments as? ByteArray
                    if (data != null) {
                        FloatingWindowManager.getInstance()?.saveScreenshotToGallery(data)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "No image data provided", null)
                    }
                }
                "saveAiConfig" -> {
                    val apiUrl = call.argument<String>("apiUrl") ?: ""
                    val apiKey = call.argument<String>("apiKey") ?: ""
                    val model = call.argument<String>("model") ?: "glm-4v-flash"
                    val systemPrompt = call.argument<String>("systemPrompt") ?: ""

                    // 保存到 SharedPreferences
                    getSharedPreferences("ai_config", Context.MODE_PRIVATE)
                        .edit()
                        .putString("api_url", apiUrl)
                        .putString("api_key", apiKey)
                        .putString("model", model)
                        .putString("system_prompt", systemPrompt)
                        .apply()

                    // 同时更新 FloatingWindowManager 实例的配置
                    FloatingWindowManager.getInstance()?.apply {
                        this.apiUrl = apiUrl
                        this.apiKey = apiKey
                        this.model = model
                        this.systemPrompt = systemPrompt
                    }

                    result.success(true)
                }
                "onAiAnswerChunk" -> {
                    // Flutter 推送 AI 答案片段
                    val chunk = call.argument<String>("chunk") ?: ""
                    FloatingWindowManager.getInstance()?.appendAiAnswer(chunk)
                    result.success(true)
                }
                "onAiAnswerError" -> {
                    // Flutter 推送 AI 错误
                    val error = call.argument<String>("error") ?: ""
                    FloatingWindowManager.getInstance()?.showAiError(error)
                    result.success(true)
                }
                "onAiAnswerStart" -> {
                    // Flutter 开始 AI 回答
                    FloatingWindowManager.getInstance()?.showAiLoading()
                    result.success(true)
                }
                "onAiAnswerDone" -> {
                    // Flutter 完成 AI 回答
                    FloatingWindowManager.getInstance()?.hideAiLoading()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestScreenCapturePermission() {
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val intent = mediaProjectionManager?.createScreenCaptureIntent()
        intent?.let {
            startActivityForResult(it, SCREEN_CAPTURE_REQUEST_CODE)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCREEN_CAPTURE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                // 授权成功，创建 MediaProjection
                val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val mediaProjection = mpManager.getMediaProjection(resultCode, data!!)
                // 设置给 FloatingWindowManager
                FloatingWindowManager.getInstance()?.setMediaProjection(mediaProjection)

                // 通知 Flutter 授权成功
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, FLOATING_CHANNEL)
                        .invokeMethod("onScreenshotPermissionGranted", null)
                }
            } else {
                // 授权失败
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, FLOATING_CHANNEL)
                        .invokeMethod("onScreenshotPermissionDenied", null)
                }
            }
        }
    }

    // 播放系统通知铃声
    private fun playNotificationSound() {
        try {
            val notification: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val ringtone = RingtoneManager.getRingtone(applicationContext, notification)
            ringtone?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // 震动指定时长（毫秒）
    private fun vibrate(duration: Long) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Android 8.0+ 使用 VibrationEffect
                vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                // Android 8.0 以下
                @Suppress("DEPRECATION")
                vibrator.vibrate(duration)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 处理深层链接
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        // 处理启动时的 Intent
        handleIntent(intent)
        // 注册区域截图广播接收器
        registerRegionCaptureReceiver()
        // 注册 AI 问题广播接收器
        registerAiQuestionReceiver()
    }

    override fun onDestroy() {
        super.onDestroy()
        regionCaptureReceiver?.let { unregisterReceiver(it) }
        aiQuestionReceiver?.let { unregisterReceiver(it) }
    }

    private fun registerRegionCaptureReceiver() {
        if (regionCaptureReceiver != null) return
        regionCaptureReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.example.flutter_application_1.REGION_CAPTURED") {
                    val data = intent.getByteArrayExtra("data")
                    data?.let {
                        runOnUiThread {
                            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                                MethodChannel(messenger, FLOATING_CHANNEL)
                                    .invokeMethod("onRegionCaptured", it)
                            }
                        }
                    }
                }
            }
        }
        val filter = IntentFilter("com.example.flutter_application_1.REGION_CAPTURED")
        registerReceiver(regionCaptureReceiver, filter)
    }

    private fun registerAiQuestionReceiver() {
        if (aiQuestionReceiver != null) return
        aiQuestionReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "com.example.flutter_application_1.AI_QUESTION") {
                    val question = intent.getStringExtra("question") ?: return
                    val imageData = intent.getByteArrayExtra("image_data") ?: return
                    // 通过 MethodChannel 通知 Flutter 调用 AI
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, FLOATING_CHANNEL)
                            .invokeMethod("onAiQuestion", mapOf(
                                "question" to question,
                                "imageData" to imageData
                            ))
                    }
                }
            }
        }
        val filter = IntentFilter("com.example.flutter_application_1.AI_QUESTION")
        registerReceiver(aiQuestionReceiver, filter)
    }

    private fun handleIntent(intent: Intent?) {
        intent?.data?.let { uri ->
            // 检查是否是 fr://lab
            if (uri.toString() == "fr://lab" || uri.path == "/lab") {
                // 通过 MethodChannel 通知 Flutter 跳转
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("navigateToLab", null)
                }
            }
        }
    }

    private fun navigateToLab() {
        // 通知 Flutter 导航到 Lab 页面
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod("navigateToLab", null)
        }
    }

    // 检查使用统计权限
    private fun checkUsagePermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            }
            return mode == AppOpsManager.MODE_ALLOWED
        }
        return false
    }

    // 打开使用统计设置页面
    private fun openUsageSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        startActivity(intent)
    }

    // 查询应用使用时长
    private fun queryAppUsage(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return emptyList()
        }

        if (!checkUsagePermission()) {
            return emptyList()
        }

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        // 获取今天的开始和结束时间
        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        // 查询使用统计
        val usageStatsList = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        // 获取 PackageManager
        val packageManager = packageManager

        // 转换为 Map 列表
        val result = mutableListOf<Map<String, Any>>()
        for (usageStats in usageStatsList) {
            // 过滤掉使用时长为0的应用
            if (usageStats.totalTimeInForeground > 0) {
                val appName = try {
                    val appInfo = packageManager.getApplicationInfo(usageStats.packageName, 0)
                    packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: Exception) {
                    usageStats.packageName
                }

                val map = mapOf(
                    "packageName" to usageStats.packageName,
                    "appName" to appName,
                    "totalTimeInForeground" to usageStats.totalTimeInForeground,
                    "lastTimeUsed" to usageStats.lastTimeUsed
                )
                result.add(map)
            }
        }

        // 按使用时长排序
        return result.sortedByDescending { it["totalTimeInForeground"] as Long }
    }
}
