package io.github.xiaodouzi.fr.native.volume

import android.content.Context
import android.media.AudioManager
import android.media.audiofx.Equalizer
import android.util.Log

/**
 * EQ 均衡器响度控制器
 *
 * 核心原理：所有 EQ 频段统一拉低 dB = 系统音量之外的"第二层音量旋钮"
 * EQ 工作在音频数据流层（PCM），在系统音量（AudioFlinger）之前
 * 因此能做到"比系统最低音量还低"
 */
class VirtualVolumeController(private val context: Context) {

    companion object {
        private const val TAG = "EqVolumeCtrl"
        // session 0 = 尝试全局音频
        private const val GLOBAL_SESSION = 0
    }

    private val audioManager: AudioManager =
        context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // EQ 实例
    private var equalizer: Equalizer? = null

    // 是否启用
    var isEnabled: Boolean = false
        private set

    // 当前虚拟音量 0.0~1.0
    var virtualVolume: Float = 1.0f
        private set

    // 当前增益 (0-100)，用于 Flutter 侧读取
    var currentGain: Int = 100
        private set

    // EQ 是否可用（设备支持）
    var isEqAvailable: Boolean = false
        private set

    // 保存的原始音量
    private var savedOriginalVolume: Int = -1

    /**
     * 初始化 EQ
     * 尝试绑定 session 0（全局），失败则 fallback 到系统音量
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
            Log.w(TAG, "EQ 初始化失败(设备不支持全局session), fallback到系统音量: ${e.message}")
        }
    }

    /**
     * 启用响度控制
     */
    fun enable() {
        if (isEnabled) return
        isEnabled = true
        // 保存原始系统音量
        if (savedOriginalVolume < 0) {
            savedOriginalVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        }
        applyVolume()
        Log.d(TAG, "启用 isEqAvailable=$isEqAvailable")
    }

    /**
     * 禁用响度控制，恢复原始状态
     */
    fun disable() {
        if (!isEnabled) return
        isEnabled = false

        // 重置 EQ 所有频段到 0dB
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

        // 恢复系统音量
        if (savedOriginalVolume >= 0) {
            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, savedOriginalVolume, 0)
            savedOriginalVolume = -1
        }
        Log.d(TAG, "禁用")
    }

    /**
     * 设置虚拟音量 (0.0~1.0)
     */
    fun setVirtualVolume(volume: Float) {
        virtualVolume = volume.coerceIn(0.0f, 1.0f)
        currentGain = (virtualVolume * 100).toInt()
        if (isEnabled) {
            applyVolume()
        }
    }

    /**
     * 核心：应用音量衰减
     *
     * 双路径策略：
     * - EQ 可用：所有频段统一设置 dB 衰减（比系统音量更精细）
     * - EQ 不可用：fallback 到系统音量控制
     */
    private fun applyVolume() {
        if (isEqAvailable) {
            applyViaEqualizer()
        } else {
            applyViaSystemVolume()
        }
    }

    /**
     * 路径1：EQ 全频段衰减
     * gainDb = -50 * (1 - v³)
     * volume=1.0 -> 0dB（无衰减）
     * volume=0.5 -> -43.75dB
     * volume=0.1 -> -49.95dB
     */
    private fun applyViaEqualizer() {
        val eq = equalizer ?: return
        try {
            val gainDb = mapVolumeToDb(virtualVolume)
            // Equalizer 使用 millibel 为单位 (1dB = 100 mB)
            val levelMb = (gainDb * 100).toInt()
            val bands = eq.numberOfBands.toInt()

            for (i in 0 until bands) {
                eq.setBandLevel(i.toShort(), levelMb.toShort())
            }

            Log.d(TAG, "EQ: volume=$virtualVolume -> ${gainDb}dB (${levelMb}mB), bands=$bands")
        } catch (e: Exception) {
            Log.e(TAG, "EQ设置失败: ${e.message}")
            // fallback
            applyViaSystemVolume()
        }
    }

    /**
     * 路径2：系统音量 fallback
     * 使用 x² 非线性映射
     */
    private fun applyViaSystemVolume() {
        val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        val mapped = (virtualVolume * virtualVolume * maxVol).toInt().coerceIn(0, maxVol)
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, mapped, 0)
        Log.d(TAG, "系统音量: volume=$virtualVolume -> system=$mapped")
    }

    /**
     * 非线性映射：volume(0~1) -> dB 衰减
     * v=1.0 -> 0dB
     * v=0.5 -> -43.75dB
     * v=0.1 -> -49.95dB
     * v=0.0 -> -50dB
     */
    private fun mapVolumeToDb(v: Float): Float {
        return -50f * (1f - v * v * v)
    }

    fun getMaxSystemVolume(): Int =
        audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)

    fun getCurrentSystemVolume(): Int =
        audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)

    /**
     * 保存原始音量（供 Service 调用）
     */
    fun saveOriginalVolume(): Int {
        if (savedOriginalVolume < 0) {
            savedOriginalVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        }
        return savedOriginalVolume
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
