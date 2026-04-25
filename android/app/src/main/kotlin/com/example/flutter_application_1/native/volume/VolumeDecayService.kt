package com.example.flutter_application_1.native.volume

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class VolumeDecayService : Service() {
    companion object {
        const val CHANNEL_ID = "volume_decay_channel"
        const val NOTIFY_ID = 9528
        const val ACTION_TURN_ON = "com.example.flutter_application_1.ACTION_TURN_ON"
        const val ACTION_TURN_OFF = "com.example.flutter_application_1.ACTION_TURN_OFF"
        const val ACTION_SET_GAIN = "com.example.flutter_application_1.ACTION_SET_GAIN"
        const val ACTION_SET_VOLUME = "com.example.flutter_application_1.ACTION_SET_VOLUME"

        private const val DEFAULT_STREAM = AudioManager.STREAM_MUSIC

        var currentGain: Int = 40
        var isRunning: Boolean = false
            private set

        private var savedVolume: Int = -1
    }

    private lateinit var audioManager: AudioManager

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TURN_OFF -> {
                restoreOriginalVolume()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SET_GAIN -> {
                val gain = intent.getIntExtra("gain", 40)
                setDecayGain(gain)
            }
            ACTION_SET_VOLUME -> {
                val volume = intent.getIntExtra("volume", -1)
                if (volume >= 0) {
                    setMediaVolume(volume)
                }
            }
            ACTION_TURN_ON -> {
                val gain = intent.getIntExtra("gain", 40)
                startForeground(NOTIFY_ID, buildNotification())
                setDecayGain(gain)
            }
            else -> {
                startForeground(NOTIFY_ID, buildNotification())
            }
        }
        return START_STICKY
    }

    private fun setDecayGain(gain: Int) {
        currentGain = gain.coerceIn(0, 100)

        // 保存原始音量
        if (savedVolume < 0) {
            savedVolume = audioManager.getStreamVolume(DEFAULT_STREAM)
        }

        // 计算衰减后的音量: 原始音量 * (gain / 100)
        if (savedVolume > 0) {
            val maxVolume = audioManager.getStreamMaxVolume(DEFAULT_STREAM)
            val targetVolume = (savedVolume * currentGain / 100f).toInt().coerceIn(0, maxVolume)
            audioManager.setStreamVolume(DEFAULT_STREAM, targetVolume, 0)
        }

        isRunning = true
        updateNotification()
    }

    private fun setMediaVolume(volume: Int) {
        val maxVolume = audioManager.getStreamMaxVolume(DEFAULT_STREAM)
        val safeVolume = volume.coerceIn(0, maxVolume)
        audioManager.setStreamVolume(DEFAULT_STREAM, safeVolume, 0)
    }

    private fun restoreOriginalVolume() {
        if (savedVolume >= 0) {
            audioManager.setStreamVolume(DEFAULT_STREAM, savedVolume, 0)
            savedVolume = -1
        }
        isRunning = false
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "响度衰减服务",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "全局音频响度衰减控制"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_speaker_phone)
            .setContentTitle("响度衰减已开启")
            .setContentText("当前增益: $currentGain%")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFY_ID, buildNotification())
    }

    override fun onDestroy() {
        super.onDestroy()
        restoreOriginalVolume()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
