package com.example.flutter_application_1

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
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

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flutter_application_1/widget"
    private val CLOCK_CHANNEL = "com.example.flutter_application_1/clock"
    private val SYSTEM_CHANNEL = "com.example.flutter_application_1/system"

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
                    val duration = call.argument<Long>("duration") ?: 3000L
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
