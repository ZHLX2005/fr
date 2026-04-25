package io.github.xiaodouzi.fr.native.volume

import android.content.Context
import android.media.AudioManager
import android.util.Log
import kotlin.math.pow

/**
 * 虚拟音量控制器
 *
 * 核心原理：用户滑杆 0.0~1.0 -> 非线性映射 -> 系统音量
 * 非线性曲线实现"比1格更低"的感知效果
 */
class VirtualVolumeController(private val context: Context) {

    companion object {
        private const val TAG = "VirtualVolumeCtrl"
        // 指数曲线 powerFactor 越大，虚拟音量"压缩"越厉害
        // 2.0 = x², 3.0 = x³, 4.0 = x⁴（更激进）
        private const val DEFAULT_POWER = 3.5f
    }

    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val maxStreamVolume: Int
        get() = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

    // 虚拟音量 0.0 ~ 1.0
    var virtualVolume: Float = 1.0f
        private set

    // 实际生效的衰减指数
    var powerFactor: Float = DEFAULT_POWER

    // 是否启用
    var isEnabled: Boolean = false
        private set

    init {
        // 恢复保存的状态
        val prefs = context.getSharedPreferences("volume_decay", Context.MODE_PRIVATE)
        virtualVolume = prefs.getFloat("virtual_volume", 1.0f)
        powerFactor = prefs.getFloat("power_factor", DEFAULT_POWER)
    }

    /**
     * 启用虚拟音量控制
     * 保存当前系统音量作为基准，然后应用虚拟音量
     */
    fun enable() {
        if (isEnabled) return
        isEnabled = true
        applyVirtualVolume()
        saveState()
        Log.d(TAG, "启用虚拟音量 powerFactor=$powerFactor")
    }

    /**
     * 禁用虚拟音量，恢复原始音量
     */
    fun disable() {
        if (!isEnabled) return
        isEnabled = false
        restoreOriginalVolume()
        saveState()
        Log.d(TAG, "禁用虚拟音量")
    }

    /**
     * 设置虚拟音量 (0.0 ~ 1.0)
     */
    fun setVirtualVolume(value: Float) {
        virtualVolume = value.coerceIn(0.0f, 1.0f)
        if (isEnabled) {
            applyVirtualVolume()
        }
        saveState()
    }

    /**
     * 设置衰减指数 (powerFactor)
     * 值越大，虚拟音量压缩越厉害（更低感知响度）
     */
    fun applyPowerFactor(exp: Float) {
        powerFactor = exp.coerceIn(1.0f, 10.0f)
        if (isEnabled) {
            applyVirtualVolume()
        }
        saveState()
    }

    /**
     * 虚拟音量转系统音量的非线性映射
     * virtualVolume=0.1, powerFactor=3.5 -> 系统音量极低
     */
    private fun virtualToSystemVolume(): Int {
        if (virtualVolume <= 0f) return 0
        val mapped = virtualVolume.toDouble().pow(powerFactor.toDouble())
        return (mapped * maxStreamVolume).toInt().coerceIn(0, maxStreamVolume)
    }

    /**
     * 应用虚拟音量到系统
     */
    private fun applyVirtualVolume() {
        val systemVol = virtualToSystemVolume()
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, systemVol, 0)
        Log.d(TAG, "apply virtual=$virtualVolume -> system=$systemVol (max=$maxStreamVolume)")
    }

    /**
     * 恢复原始音量
     */
    private fun restoreOriginalVolume() {
        val original = savedOriginalVolume
        if (original >= 0) {
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, original, 0)
            savedOriginalVolume = -1
        }
    }

    private var savedOriginalVolume: Int = -1

    /**
     * 保存原始音量（首次启用时）
     */
    fun saveOriginalVolume(): Int {
        if (savedOriginalVolume < 0) {
            savedOriginalVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        }
        return savedOriginalVolume
    }

    private fun saveState() {
        context.getSharedPreferences("volume_decay", Context.MODE_PRIVATE)
            .edit()
            .putFloat("virtual_volume", virtualVolume)
            .putFloat("exponent", powerFactor)
            .apply()
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
    fun getMaxSystemVolume(): Int = maxStreamVolume

    /**
     * 获取当前虚拟音量百分比 (0~100)
     */
    fun getVirtualVolumePercent(): Int = (virtualVolume * 100).toInt()
}
