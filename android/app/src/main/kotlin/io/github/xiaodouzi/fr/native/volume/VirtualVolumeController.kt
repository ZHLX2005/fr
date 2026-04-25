package io.github.xiaodouzi.fr.native.volume

import android.content.Context
import android.media.audiofx.Equalizer
import android.util.Log

/**
 * EQ 均衡器响度控制器
 *
 * 核心：只通过 EQ 合成衰减，不调系统音量
 * 所有频段统一拉低 dB = 在 PCM 数据流层做音量控制
 * EQ 工作在 AudioTrack 输出之前，等于在"音量旋钮"之前做处理
 */
class VirtualVolumeController(private val context: Context) {

    companion object {
        private const val TAG = "EqVolumeCtrl"
        // session 0 = 尝试绑定全局音频
        private const val GLOBAL_SESSION = 0
    }

    private var equalizer: Equalizer? = null

    var isEnabled: Boolean = false
        private set

    var virtualVolume: Float = 1.0f
        private set

    var currentGain: Int = 100
        private set

    // EQ 是否可用
    var isEqAvailable: Boolean = false
        private set

    /**
     * 初始化 EQ，尝试绑定 session 0（全局）
     */
    fun init() {
        try {
            equalizer = Equalizer(0, GLOBAL_SESSION).apply {
                enabled = true
            }
            isEqAvailable = true
            Log.d(TAG, "EQ 初始化成功, bands=${equalizer?.numberOfBands}")
        } catch (e: Exception) {
            isEqAvailable = false
            Log.w(TAG, "EQ 全局绑定失败: ${e.message}")
        }
    }

    /**
     * 启用：保存当前 EQ 设置，应用衰减
     */
    fun enable() {
        if (isEnabled) return
        isEnabled = true
        applyVolume()
        Log.d(TAG, "启用 EQ 响度控制")
    }

    /**
     * 禁用：所有频段恢复到 0dB，不碰系统音量
     */
    fun disable() {
        if (!isEnabled) return
        isEnabled = false

        if (isEqAvailable) {
            try {
                val bands = equalizer?.numberOfBands?.toInt() ?: 0
                for (i in 0 until bands) {
                    equalizer?.setBandLevel(i.toShort(), 0.toShort())
                }
            } catch (e: Exception) {
                Log.w(TAG, "重置EQ失败: ${e.message}")
            }
        }
        Log.d(TAG, "禁用 EQ 响度控制")
    }

    /**
     * 设置虚拟音量 (0.0~1.0)，通过 EQ 合成衰减
     */
    fun setVirtualVolume(volume: Float) {
        virtualVolume = volume.coerceIn(0.0f, 1.0f)
        currentGain = (virtualVolume * 100).toInt()
        if (isEnabled) {
            applyVolume()
        }
    }

    /**
     * 核心：只通过 EQ band level 合成音量衰减
     * 不调用任何 AudioManager.setStreamVolume
     *
     * 映射曲线: volume(0~1) -> dB
     * v=1.0 -> 0dB (无衰减)
     * v=0.5 -> -43.75dB
     * v=0.1 -> -49.95dB
     * v=0.0 -> -50dB
     */
    private fun applyVolume() {
        if (!isEqAvailable) {
            Log.w(TAG, "EQ 不可用，无法进行响度控制")
            return
        }

        val eq = equalizer ?: return
        try {
            // volume -> dB 映射
            val gainDb = mapVolumeToDb(virtualVolume)
            // Equalizer 单位是 millibel (1dB = 100mB)
            val levelMb = (gainDb * 100).toInt()
            val bands = eq.numberOfBands.toInt()

            for (i in 0 until bands) {
                eq.setBandLevel(i.toShort(), levelMb.toShort())
            }

            Log.d(TAG, "EQ 合成: volume=$virtualVolume -> ${gainDb}dB ($levelMb mB)")
        } catch (e: Exception) {
            Log.e(TAG, "EQ 设置失败: ${e.message}")
        }
    }

    /**
     * 非线性映射: v(0~1) -> dB 衰减
     * 使用 x³ 曲线，低音量时压缩更激进
     */
    private fun mapVolumeToDb(v: Float): Float {
        return -50f * (1f - v * v * v)
    }

    /**
     * 释放资源
     */
    fun release() {
        equalizer?.release()
        equalizer = null
        isEqAvailable = false
    }
}
