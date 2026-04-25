package io.github.xiaodouzi.fr.native.volume

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// 音量衰减 MethodChannel
class VolumeChannel(messenger: BinaryMessenger, private val context: Context) {
    companion object {
        const val NAME = "io.github.xiaodouzi.fr/volume"
    }

    private val channel = MethodChannel(messenger, NAME).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "turnOn" -> {
                    val gain = call.argument<Int>("gain") ?: 40
                    val intent = Intent(context, VolumeDecayService::class.java).apply {
                        action = VolumeDecayService.ACTION_TURN_ON
                        putExtra("gain", gain)
                    }
                    startService(intent)
                    result.success(true)
                }
                "turnOff" -> {
                    val intent = Intent(context, VolumeDecayService::class.java).apply {
                        action = VolumeDecayService.ACTION_TURN_OFF
                    }
                    context.startService(intent)
                    result.success(true)
                }
                "setGain" -> {
                    val gain = call.argument<Int>("gain") ?: 40
                    val intent = Intent(context, VolumeDecayService::class.java).apply {
                        action = VolumeDecayService.ACTION_SET_GAIN
                        putExtra("gain", gain)
                    }
                    context.startService(intent)
                    result.success(true)
                }
                "getGain" -> {
                    result.success(VolumeDecayService.currentGain)
                }
                "isRunning" -> {
                    result.success(VolumeDecayService.isRunning)
                }
                "setVolume" -> {
                    val volume = call.argument<Int>("volume") ?: -1
                    val intent = Intent(context, VolumeDecayService::class.java).apply {
                        action = VolumeDecayService.ACTION_SET_VOLUME
                        putExtra("volume", volume)
                    }
                    context.startService(intent)
                    result.success(true)
                }
                "getMaxVolume" -> {
                    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    result.success(audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
                }
                "getCurrentVolume" -> {
                    val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    result.success(audioManager.getStreamVolume(AudioManager.STREAM_MUSIC))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }
}
