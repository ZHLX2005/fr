package io.github.xiaodouzi.fr.native.volume

import android.content.Context
import android.media.AudioManager
import android.os.Parcel
import android.util.Log
import rikka.shizuku.Shizuku
import rikka.shizuku.SystemServiceHelper

/**
 * Shizuku 音量控制器
 *
 * 通过 Shizuku 获取特权 IBinder 调用 AudioService
 * 拥有 ADB 级别的音频控制权限
 */
class ShizukuVolumeController(private val context: Context) {

    companion object {
        private const val TAG = "ShizukuVolumeCtrl"
    }

    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // 原始音量（启动时保存）
    private var savedVolume: Int = -1

    var isEnabled: Boolean = false
        private set

    var currentGain: Int = 100
        private set

    /**
     * 检查 Shizuku 是否可用
     */
    fun isShizukuAvailable(): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (e: Exception) {
            Log.w(TAG, "Shizuku not available: ${e.message}")
            false
        }
    }

    /**
     * 检查 Shizuku 权限
     */
    fun hasPermission(): Boolean {
        return try {
            Shizuku.checkSelfPermission() == android.content.pm.PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 启用音量控制
     */
    fun enable() {
        if (isEnabled) return
        savedVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        isEnabled = true
        Log.d(TAG, "启用 Shizuku 音量控制，原始音量=$savedVolume")
    }

    /**
     * 禁用，恢复原始音量
     */
    fun disable() {
        if (!isEnabled) return
        isEnabled = false
        if (savedVolume >= 0) {
            setStreamVolumeViaShizuku(savedVolume)
            savedVolume = -1
        }
        Log.d(TAG, "禁用 Shizuku 音量控制")
    }

    /**
     * 设置音量 (0-100)
     * 通过 Shizuku 特权调用 AudioService
     */
    fun setVolume(gain: Int) {
        currentGain = gain.coerceIn(0, 100)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val targetVolume = mapGainToVolume(currentGain, maxVolume)
        setStreamVolumeViaShizuku(targetVolume)
        Log.d(TAG, "setVolume gain=$currentGain -> system=$targetVolume")
    }

    /**
     * 通过 Shizuku 调用 AudioService.setStreamVolume
     *
     * 使用 SystemServiceHelper 获取特权 IBinder
     * 再通过 transactRemote 调用 setStreamVolume 方法
     */
    private fun setStreamVolumeViaShizuku(volume: Int) {
        try {
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val safeVolume = volume.coerceIn(0, maxVol)

            // 方法1: 直接用 Shizuku 特权调用 AudioService
            val binder = SystemServiceHelper.getSystemService("audio")
            if (binder != null) {
                // 构造 setStreamVolume 的 Parcel 数据
                // API signature: setStreamVolume(int streamType, int index, int flags, String callingPackage)
                val data = Parcel.obtain()
                val reply = Parcel.obtain()
                try {
                    data.writeInterfaceToken("android.media.IAudioService")
                    data.writeInt(AudioManager.STREAM_MUSIC)  // streamType
                    data.writeInt(safeVolume)                  // index
                    data.writeInt(0)                           // flags (no UI, no sound)
                    data.writeString(context.opPackageName)    // callingPackage

                    // setStreamVolume 的 transaction code
                    // Android 10-15: transaction code 通常在 3-16 范围
                    // 通过 SystemServiceHelper 获取正确的 code
                    val transactionCode = SystemServiceHelper.getTransactionCode(
                        "android.media.IAudioService",
                        "setStreamVolume"
                    )

                    if (transactionCode != null) {
                        binder.transact(transactionCode, data, reply, 0)
                        reply.readException()
                        Log.d(TAG, "setStreamVolume via Shizuku IBinder: $safeVolume")
                        return
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "IBinder transact 失败: ${e.message}")
                } finally {
                    data.recycle()
                    reply.recycle()
                }
            }

            // 方法2: 备用 - 使用 media shell 命令
            execMediaCommand(safeVolume)

        } catch (e: Exception) {
            Log.e(TAG, "设置音量失败: ${e.message}")
        }
    }

    /**
     * 备用方案: 通过 Shizuku 执行 media shell 命令
     * media volume --stream 3 --set <volume>
     */
    private fun execMediaCommand(volume: Int) {
        try {
            val cmd = "media volume --stream 3 --set $volume"
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", cmd))
            val exitCode = process.waitFor()
            Log.d(TAG, "media command exit=$exitCode for volume=$volume")
        } catch (e: Exception) {
            Log.e(TAG, "media command 失败: ${e.message}")
            // 最后回退到 AudioManager
            try {
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, volume, 0)
            } catch (ex: Exception) {
                Log.e(TAG, "AudioManager 也失败: ${ex.message}")
            }
        }
    }

    /**
     * 非线性映射: gain(0-100) -> 系统音量
     * gain 越低，压缩越厉害
     */
    private fun mapGainToVolume(gain: Int, maxVol: Int): Int {
        if (gain <= 0) return 0
        val v = gain / 100f
        // x³ 曲线，越低越压缩
        val mapped = (v * v * v * maxVol).toInt()
        return mapped.coerceIn(0, maxVol)
    }

    /**
     * 获取当前系统音量
     */
    fun getCurrentSystemVolume(): Int {
        return audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
    }

    /**
     * 获取最大系统音量
     */
    fun getMaxSystemVolume(): Int {
        return audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
    }
}
