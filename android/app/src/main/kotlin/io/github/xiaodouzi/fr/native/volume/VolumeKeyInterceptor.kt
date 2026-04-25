package io.github.xiaodouzi.fr.native.volume

import android.content.Context
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.util.Log
import android.view.KeyEvent

/**
 * 音量键拦截器
 *
 * 使用 MediaSession 拦截音量键，自己维护虚拟音量
 * 物理音量键 -> 虚拟音量系统 -> 系统音量
 */
class VolumeKeyInterceptor(private val context: Context) {

    companion object {
        private const val TAG = "VolumeKeyInterceptor"
    }

    private var mediaSession: MediaSession? = null
    private var callback: VolumeKeyCallback? = null

    interface VolumeKeyCallback {
        fun onVolumeKeyDown(): Float
    }

    /**
     * 启动拦截
     */
    fun start(callback: VolumeKeyCallback) {
        this.callback = callback

        mediaSession = MediaSession(context, "VolumeDecaySession").apply {
            setCallback(MediaSessionCallback())
            setPlaybackState(PlaybackState.Builder()
                .setState(PlaybackState.STATE_PLAYING, 0, 1.0f)
                .build())
            isActive = true
        }

        Log.d(TAG, "音量键拦截已启动")
    }

    /**
     * 停止拦截
     */
    fun stop() {
        mediaSession?.apply {
            isActive = false
            release()
        }
        mediaSession = null
        callback = null
        Log.d(TAG, "音量键拦截已停止")
    }

    private inner class MediaSessionCallback : MediaSession.Callback() {

        override fun onMediaButtonEvent(event: android.content.Intent): Boolean {
            val keyEvent = event.getParcelableExtra<KeyEvent>(android.content.Intent.EXTRA_KEY_EVENT)
                ?: return false

            Log.d(TAG, "收到MediaButton事件: keyCode=$keyEvent.keyCode action=$keyEvent.action")

            if (keyEvent.action == KeyEvent.ACTION_DOWN) {
                when (keyEvent.keyCode) {
                    KeyEvent.KEYCODE_VOLUME_UP,
                    KeyEvent.KEYCODE_VOLUME_DOWN -> {
                        callback?.onVolumeKeyDown()
                        return true
                    }
                }
            }
            return super.onMediaButtonEvent(event)
        }
    }
}
