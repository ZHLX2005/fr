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
        Log.d("VolumeDecayService", "onCreate Engine可用=$isEngineAvailable")
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
                val gain = intent.getIntExtra("gain", currentGain)
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
        saveGain(currentGain)
        Log.d("VolumeDecayService", "turnOff")
    }

    private fun setGain(gain: Int) {
        currentGain = gain.coerceIn(0, 100)
        if (isEngineAvailable) {
            applyGain(currentGain)
        }
        saveGain(currentGain)
    }

    private fun setVolume(volume: Int) {
        currentGain = volume.coerceIn(0, 100)
        if (isEngineAvailable) {
            applyGain(currentGain)
        }
    }

    /**
     * 将 gain (0-100) 转换为 LoudnessEnhancer 增益
     * gain 越低 → 响度衰减越大
     * LoudnessEnhancer targetGain: 0 = 无增益, 2000 = +20dB
     * 通过 EQ 所有频段统一拉低来实现衰减
     */
    private fun applyGain(gain: Int) {
        if (!isEngineAvailable) return
        try {
            val gainDb = mapGainToDb(gain)
            val gainMb = (gainDb * 100).toInt()
            audioFxEngine.setAllBandLevels(gainMb)
            audioFxEngine.setLoudnessGain(0)
            Log.d("VolumeDecayService", "applyGain: gain=$gain -> ${gainDb}dB ($gainMb mB)")
        } catch (e: Exception) {
            Log.e("VolumeDecayService", "applyGain 失败: ${e.message}")
        }
    }

    /**
     * 非线性映射: gain(0-100) -> dB 衰减
     * 使用 x³ 曲线，低音量时压缩更激进
     */
    private fun mapGainToDb(gain: Int): Float {
        if (gain <= 0) return -50f
        val v = gain / 100f
        return -50f * (1f - v * v * v)
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

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("音量衰减运行中")
            .setContentText("增益: $currentGain%")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun saveGain(gain: Int) {
        getSharedPreferences("volume_decay_prefs", Context.MODE_PRIVATE)
            .edit()
            .putInt("last_gain", gain)
            .apply()
    }
}
