package com.example.flutter_application_1

import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flutter_application_1/widget"
    private val CLOCK_CHANNEL = "com.example.flutter_application_1/clock"

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
}
