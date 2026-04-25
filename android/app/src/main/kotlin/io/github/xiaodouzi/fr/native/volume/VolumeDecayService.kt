package io.github.xiaodouzi.fr.native.volume

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * 音量衰减服务
 *
 * 通过 Shizuku 执行 shell 命令控制全局音量
 * Shizuku 让 App 拥有 ADB 级别的音频控制权限
 */
class VolumeDecayService : Service() {

    companion object {
        const val ACTION_TURN_ON = "io.github.xiaodouzi.fr.ACTION_TURN_ON"
        const val ACTION_TURN_OFF = "io.github.xiaodouzi.fr.ACTION_TURN_OFF"
        const val ACTION_SET_GAIN = "io.github.xiaodouzi.fr.ACTION_SET_GAIN"
        const val ACTION_SET_VOLUME = "io.github.xiaodouzi.fr.ACTION_SET_VOLUME"

        var currentGain: Int = 40
            private set

        var isRunning: Boolean = false
            private set

        var isShizukuAvailable: Boolean = false
            private set
    }

    private lateinit var shizukuController: ShizukuVolumeController

    override fun onCreate() {
        super.onCreate()
        shizukuController = ShizukuVolumeController(this)
        isShizukuAvailable = shizukuController.isShizukuAvailable()
        Log.d("VolumeDecayService", "onCreate Shizuku可用=$isShizukuAvailable")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TURN_OFF -> {
                turnOff()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SET_GAIN -> {
                val gain = intent.getIntExtra("gain", currentGain)
                setGain(gain)
            }
            ACTION_SET_VOLUME -> {
                val volume = intent.getIntExtra("volume", -1)
                if (volume >= 0) {
                    setVolume(volume)
                }
            }
            ACTION_TURN_ON -> {
                val gain = intent.getIntExtra("gain", currentGain)
                turnOn(gain)
            }
        }
        return START_STICKY
    }

    private fun turnOn(gain: Int) {
        currentGain = gain.coerceIn(0, 100)
        shizukuController.enable()
        shizukuController.setVolume(currentGain)
        isRunning = true
        saveGain(currentGain)
        Log.d("VolumeDecayService", "turnOn gain=$currentGain Shizuku=$isShizukuAvailable")
    }

    private fun turnOff() {
        shizukuController.disable()
        isRunning = false
        saveGain(currentGain)
        Log.d("VolumeDecayService", "turnOff")
    }

    private fun setGain(gain: Int) {
        currentGain = gain.coerceIn(0, 100)
        shizukuController.setVolume(currentGain)
        saveGain(currentGain)
    }

    private fun setVolume(volume: Int) {
        val maxVol = shizukuController.getMaxSystemVolume()
        val gain = if (maxVol > 0) (volume * 100 / maxVol) else 100
        currentGain = gain.coerceIn(0, 100)
        shizukuController.setVolume(currentGain)
    }

    override fun onDestroy() {
        shizukuController.disable()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun loadSavedGain(): Int {
        return getSharedPreferences("volume_decay_prefs", Context.MODE_PRIVATE)
            .getInt("last_gain", 40)
    }

    private fun saveGain(gain: Int) {
        getSharedPreferences("volume_decay_prefs", Context.MODE_PRIVATE)
            .edit()
            .putInt("last_gain", gain)
            .apply()
    }
}
