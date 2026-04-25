package io.github.xiaodouzi.fr.native.clock

import android.app.Activity
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// 时钟相关 MethodChannel
class ClockChannel(
    messenger: BinaryMessenger,
    private val activity: Activity
) {
    companion object {
        const val NAME = "io.github.xiaodouzi.fr/clock"
    }

    private val channel = MethodChannel(messenger, NAME).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "playNotificationSound" -> {
                    playNotificationSound()
                    result.success(null)
                }
                "vibrate" -> {
                    val duration = (call.argument<Int>("duration") ?: 300).toLong()
                    vibrate(duration)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun playNotificationSound() {
        try {
            val notification: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val ringtone = RingtoneManager.getRingtone(activity, notification)
            ringtone?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun vibrate(duration: Long) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vibratorManager = activity.getSystemService(android.content.Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                vibratorManager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                activity.getSystemService(android.content.Context.VIBRATOR_SERVICE) as Vibrator
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(duration)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
