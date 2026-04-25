package io.github.xiaodouzi.fr.native.volume

import android.content.Context
import android.media.AudioManager
import android.util.Log
import rikka.shizuku.Shizuku
import rikka.shizuku.ShizukuRemoteProcess

/**
 * Shizuku 音量控制器
 *
 * 通过 Shizuku (ADB shell) 执行系统命令来控制全局音量
 * 比普通 App 权限高，可操作 system service
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
     * 请求 Shizuku 权限
     */
    fun requestPermission(requestCode: Int, listener: Shizuku.OnRequestPermissionResultListener) {
        try {
            Shizuku.addRequestPermissionResultListener(listener)
            Shizuku.requestPermission(requestCode)
        } catch (e: Exception) {
            Log.e(TAG, "请求Shizuku权限失败: ${e.message}")
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
            setSystemVolume(savedVolume)
            savedVolume = -1
        }
        Log.d(TAG, "禁用 Shizuku 音量控制")
    }

    /**
     * 设置音量 (0-100)
     * 通过 Shizuku 调用 system service 实现
     */
    fun setVolume(gain: Int) {
        currentGain = gain.coerceIn(0, 100)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        // 非线性映射: gain -> 系统音量
        val targetVolume = mapGainToVolume(currentGain, maxVolume)
        setSystemVolume(targetVolume)
        Log.d(TAG, "setVolume gain=$currentGain -> system=$targetVolume")
    }

    /**
     * 核心: 通过 Shizuku 执行 shell 命令设置系统音量
     */
    private fun setSystemVolume(volume: Int) {
        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val safeVolume = volume.coerceIn(0, maxVol)

        try {
            // 方法1: 使用 service call 直接操作 AudioService
            val cmd = "service call audio ${getAudioServiceCallCode()} i32 $safeVolume i32 1"
            execShizukuCommand(cmd)
        } catch (e: Exception) {
            Log.e(TAG, "设置音量失败: ${e.message}")
        }
    }

    /**
     * 获取 AudioService 的 call code
     * 不同 Android 版本 code 不同
     */
    private fun getAudioServiceCallCode(): String {
        return when (android.os.Build.VERSION.SDK_INT) {
            in 29..34 -> "13"  // setStreamVolume
            else -> "13"
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
     * 通过 Shizuku 执行 shell 命令 (public API)
     */
    private fun execShizukuCommand(command: String): String? {
        return try {
            val process: ShizukuRemoteProcess = Shizuku.newProcess(
                arrayOf("sh", "-c", command),
                null,
                "/"
            )
            val stdout = process.inputStream.bufferedReader().readText().trim()
            val exitCode = process.waitFor()
            Log.d(TAG, "exec: '$command' -> exit=$exitCode stdout='$stdout'")
            stdout
        } catch (e: Exception) {
            Log.e(TAG, "execShizukuCommand 失败: ${e.message}")
            null
        }
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
