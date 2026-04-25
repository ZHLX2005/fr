package io.github.xiaodouzi.fr.native.volume

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 音量衰减服务
 *
 * 通过 AudioFxEngine (LoudnessEnhancer + Equalizer) 全局挂载
 * sessionId=0 作用于所有音频输出，无需特殊权限
 * 前台 Service 保活
 */
class VolumeDecayService : Service() {

    companion object {
        const val ACTION_TURN_ON = "io.github.xiaodouzi.fr.ACTION_TURN_ON"
        const val ACTION_TURN_OFF = "io.github.xiaodouzi.fr.ACTION_TURN_OFF"
        const val ACTION_SET_GAIN = "io.github.xiaodouzi.fr.ACTION_SET_GAIN"
        const val ACTION_SET_VOLUME = "io.github.xiaodouzi.fr.ACTION_SET_VOLUME"

        const val NOTIF_ID = 1001
        const val CHANNEL_ID = "volume_decay"

        // 最大 EQ 衰减量 (millibels)
        const val MAX_EQ_ATTENUATION = 2000  // -20 dB

        var currentGain: Int = 40
            private set

        var isRunning: Boolean = false
            private set

        var isEngineAvailable: Boolean = false
            private set
    }

    private lateinit var audioFxEngine: AudioFxEngine

    override fun onCreate() {
        super.onCreate()
        audioFxEngine = AudioFxEngine()
        audioFxEngine.initialize()
        isEngineAvailable = audioFxEngine.isInitialized
        // 恢复上次保存的增益
        currentGain = loadSavedGain()
        Log.d("VolumeDecayService", "onCreate Engine可用=$isEngineAvailable 上次增益=$currentGain")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TURN_OFF -> {
                turnOff()
                stopForeground(STOP_FOREGROUND_REMOVE)
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
                // 有 extra 时用 extra，没有则用保存的值
                val hasGain = intent.hasExtra("gain")
                val gain = if (hasGain) intent.getIntExtra("gain", currentGain) else currentGain
                turnOn(gain)
            }
        }
        return START_STICKY
    }

    private fun turnOn(gain: Int) {
        currentGain = gain.coerceIn(0, 100)
        audioFxEngine.initialize()
        isEngineAvailable = audioFxEngine.isInitialized

        if (isEngineAvailable) {
            applyGain(currentGain)
            audioFxEngine.setEnabled(true)
        }

        isRunning = true
        saveGain(currentGain)
        startForeground(NOTIF_ID, buildNotification())
        Log.d("VolumeDecayService", "turnOn gain=$currentGain engine=$isEngineAvailable")
    }

    private fun turnOff() {
        audioFxEngine.setEnabled(false)
        isRunning = false
        // 关闭时不保存 0，保留当前增益以便重新开启
        Log.d("VolumeDecayService", "turnOff")
    }

    private fun setGain(gain: Int) {
        currentGain = gain.coerceIn(0, 100)
        if (isEngineAvailable) {
            applyGain(currentGain)
        }
        saveGain(currentGain)
        // 更新前台通知
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIF_ID, buildNotification())
    }

    private fun setVolume(volume: Int) {
        currentGain = volume.coerceIn(0, 100)
        if (isEngineAvailable) {
            applyGain(currentGain)
        }
    }

    /**
     * 将 gain (0-100) 转换为 EQ 衰减量
     * gain = 100 → 0dB 衰减（无变化）
     * gain = 0 → -20dB 衰减（几乎静音）
     * gain = 40 → -12dB 衰减（线性映射）
     *
     * 映射公式: attenuationDb = -MAX_EQ_ATTENUATION * (1 - gain/100)
     * 即: 保留多少百分比的音量，就衰减掉剩下的 dB 量
     */
    private fun applyGain(gain: Int) {
        if (!isEngineAvailable) return
        try {
            // 线性映射: gain 直接等于"保留的音量百分比"
            // gain=100 → 0% 衰减，gain=0 → 100% 衰减
            val attenuationRatio = (100 - gain) / 100f
            val attenuationMb = (attenuationRatio * MAX_EQ_ATTENUATION).toInt()

            audioFxEngine.setAllBandLevels(-attenuationMb)
            audioFxEngine.setLoudnessGain(0)

            Log.d("VolumeDecayService", "applyGain: gain=$gain → 保留${gain}% → 衰减$attenuationMb mB")
        } catch (e: Exception) {
            Log.e("VolumeDecayService", "applyGain 失败: ${e.message}")
        }
    }

    override fun onDestroy() {
        audioFxEngine.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "音量衰减",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setShowBadge(false)
                description = "音量衰减服务运行中"
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val percentText = if (currentGain >= 100) "无衰减"
                           else if (currentGain <= 0) "静音"
                           else "保留 ${currentGain}%"

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("音量衰减")
            .setContentText(percentText)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun saveGain(gain: Int) {
        getSharedPreferences("volume_decay_prefs", Context.MODE_PRIVATE)
            .edit()
            .putInt("last_gain", gain)
            .apply()
    }

    private fun loadSavedGain(): Int {
        return getSharedPreferences("volume_decay_prefs", Context.MODE_PRIVATE)
            .getInt("last_gain", 40)
    }
}
