package io.github.xiaodouzi.fr.native.volume

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.util.Log

/**
 * 音量衰减服务
 *
 * 使用虚拟音量曲线实现"比系统音量更低"的感知响度控制
 * 核心: x^n 非线性映射
 */
class VolumeDecayService : Service() {

    companion object {
        const val ACTION_TURN_ON = "io.github.xiaodouzi.fr.ACTION_TURN_ON"
        const val ACTION_TURN_OFF = "io.github.xiaodouzi.fr.ACTION_TURN_OFF"
        const val ACTION_SET_GAIN = "io.github.xiaodouzi.fr.ACTION_SET_GAIN"
        const val ACTION_SET_VOLUME = "io.github.xiaodouzi.fr.ACTION_SET_VOLUME"
        const val ACTION_SET_EXPONENT = "io.github.xiaodouzi.fr.ACTION_SET_EXPONENT"

        var currentGain: Int = 40
            private set

        var isRunning: Boolean = false
            private set
    }

    private lateinit var controller: VirtualVolumeController
    private lateinit var keyInterceptor: VolumeKeyInterceptor

    override fun onCreate() {
        super.onCreate()
        controller = VirtualVolumeController(this)
        keyInterceptor = VolumeKeyInterceptor(this)

        currentGain = loadSavedGain()
        isRunning = controller.isEnabled
        Log.d("VolumeDecayService", "onCreate isRunning=$isRunning currentGain=$currentGain")
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
            ACTION_SET_EXPONENT -> {
                val exponent = intent.getFloatExtra("exponent", 3.5f)
                setExponent(exponent)
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
        controller.saveOriginalVolume()
        controller.setVirtualVolume(currentGain / 100f)
        controller.enable()

        keyInterceptor.start(object : VolumeKeyInterceptor.VolumeKeyCallback {
            override fun onVolumeKeyDown(): Float {
                val step = 0.05f
                val current = controller.virtualVolume
                val newVolume = (current + step).coerceIn(0f, 1f)
                controller.setVirtualVolume(newVolume)
                currentGain = (newVolume * 100).toInt()
                return newVolume
            }
        })

        isRunning = true
        saveGain(currentGain)
        Log.d("VolumeDecayService", "turnOn gain=$currentGain powerFactor=${controller.powerFactor}")
    }

    private fun turnOff() {
        keyInterceptor.stop()
        controller.disable()
        isRunning = false
        saveGain(currentGain)
        Log.d("VolumeDecayService", "turnOff")
    }

    private fun setGain(gain: Int) {
        currentGain = gain.coerceIn(0, 100)
        controller.setVirtualVolume(currentGain / 100f)
        saveGain(currentGain)
    }

    private fun setExponent(exponent: Float) {
        controller.applyPowerFactor(exponent)
    }

    private fun setVolume(volume: Int) {
        val maxVol = controller.getMaxSystemVolume()
        val virtual = if (maxVol > 0) volume.toFloat() / maxVol else 1f
        controller.setVirtualVolume(virtual)
        currentGain = (virtual * 100).toInt()
    }

    override fun onDestroy() {
        keyInterceptor.stop()
        controller.disable()
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
