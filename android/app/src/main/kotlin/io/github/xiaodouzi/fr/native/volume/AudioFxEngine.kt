package io.github.xiaodouzi.fr.native.volume

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.util.Log

/**
 * 全局音频效果引擎
 *
 * 通过 sessionId=0 挂载到 Output Mix，无需任何特殊权限
 * LoudnessEnhancer 实现平滑响度衰减（ITU BS.1770-4 限幅）
 * Equalizer 细调频响曲线
 * BassBoost 增强低音
 */
class AudioFxEngine {

    private var eq: Equalizer? = null
    private var loudness: LoudnessEnhancer? = null
    private var bass: BassBoost? = null

    var isInitialized: Boolean = false
        private set

    var isEnabled: Boolean = false
        private set

    companion object {
        private const val TAG = "AudioFxEngine"
        const val SESSION_GLOBAL = 0
        const val BAND_COUNT = 5
        const val GAIN_MIN_MB = -1500  // Int representation of Short
        const val GAIN_MAX_MB = 1500
    }

    /**
     * 初始化并挂载全部效果器到 Output Mix
     */
    fun initialize() {
        release()

        try {
            eq = Equalizer(0, SESSION_GLOBAL).apply {
                enabled = true
            }
            loudness = LoudnessEnhancer(SESSION_GLOBAL).apply {
                enabled = true
            }
            bass = BassBoost(0, SESSION_GLOBAL).apply {
                enabled = true
            }
            isInitialized = true
            Log.d(TAG, "AudioFx 初始化成功: EQ bands=${eq?.numberOfBands}")
        } catch (e: Exception) {
            isInitialized = false
            Log.e(TAG, "AudioFx 初始化失败: ${e.message}")
        }
    }

    // ── 响度增益（核心功能）────────────────────────────────────────────────────

    /**
     * 设置响度增益
     * @param gainMb 单位 millibels，推荐范围 0–2000（0 dB ~ +20 dB）
     */
    fun setLoudnessGain(gainMb: Int) {
        if (!isInitialized) return
        try {
            val targetGain = gainMb.coerceIn(0, 2000)
            loudness?.setTargetGain(targetGain)
            Log.d(TAG, "setLoudnessGain: ${targetGain}mB")
        } catch (e: Exception) {
            Log.e(TAG, "setLoudnessGain 失败: ${e.message}")
        }
    }

    // ── EQ ──────────────────────────────────────────────────────────────────

    /**
     * 设置指定频段的增益
     * @param band 0–4
     * @param gainMb 单位 millibels，±1500
     */
    fun setEqBand(band: Int, gainMb: Int) {
        if (!isInitialized) return
        val clamped = gainMb.coerceIn(GAIN_MIN_MB, GAIN_MAX_MB)
        try {
            eq?.setBandLevel(band.toShort(), clamped.toShort())
        } catch (e: Exception) {
            Log.e(TAG, "setEqBand 失败: ${e.message}")
        }
    }

    /**
     * 设置所有频段统一增益（简化模式，用于整体音量调节）
     */
    fun setAllBandLevels(gainMb: Int) {
        if (!isInitialized) return
        val clamped = gainMb.coerceIn(GAIN_MIN_MB, GAIN_MAX_MB)
        try {
            val bands = eq?.numberOfBands?.toInt() ?: BAND_COUNT
            for (i in 0 until bands) {
                eq?.setBandLevel(i.toShort(), clamped.toShort())
            }
        } catch (e: Exception) {
            Log.e(TAG, "setAllBandLevels 失败: ${e.message}")
        }
    }

    /**
     * 获取频段中心频率（Hz），用于 UI 轴标
     */
    fun getBandCenterFreqs(): IntArray {
        val bands = eq?.numberOfBands?.toInt() ?: BAND_COUNT
        return IntArray(bands) { band ->
            (eq?.getCenterFreq(band.toShort()) ?: 0) / 1000
        }
    }

    // ── 低音增强 ─────────────────────────────────────────────────────────────

    /**
     * 设置低音增强
     * @param strength 0–1000
     */
    fun setBassStrength(strength: Int) {
        if (!isInitialized) return
        val clamped = strength.coerceIn(0, 1000)
        try {
            bass?.setStrength(clamped.toShort())
        } catch (e: Exception) {
            Log.e(TAG, "setBassStrength 失败: ${e.message}")
        }
    }

    // ── 启用/禁用 ─────────────────────────────────────────────────────────────

    fun setEnabled(enabled: Boolean) {
        if (!isInitialized) return
        isEnabled = enabled
        try {
            eq?.enabled = enabled
            loudness?.enabled = enabled
            bass?.enabled = enabled
        } catch (e: Exception) {
            Log.e(TAG, "setEnabled 失败: ${e.message}")
        }
    }

    fun release() {
        isEnabled = false
        isInitialized = false
        try {
            eq?.release(); eq = null
            loudness?.release(); loudness = null
            bass?.release(); bass = null
        } catch (e: Exception) {
            Log.e(TAG, "release 失败: ${e.message}")
        }
        Log.d(TAG, "AudioFx 已释放")
    }
}
