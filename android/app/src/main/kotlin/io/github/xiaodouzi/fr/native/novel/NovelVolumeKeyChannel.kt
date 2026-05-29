package io.github.xiaodouzi.fr.native.novel

import android.content.Context
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.util.Log
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class NovelVolumeKeyChannel(
    messenger: BinaryMessenger,
    private val context: Context,
) {
    companion object {
        private const val TAG = "NovelVolumeKeyChannel"
        const val NAME = "lab.novel_reader.volume_key_turn"
    }

    private val channel = MethodChannel(messenger, NAME)
    private var mediaSession: MediaSession? = null
    private var active = false
    private var enabled = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setActive" -> {
                    val value = call.arguments as? Boolean ?: false
                    if (value) start() else stop()
                    result.success(true)
                }
                "setEnabled" -> {
                    enabled = call.arguments as? Boolean ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun start() {
        if (active) return
        active = true

        mediaSession = MediaSession(context, "NovelVolumeKeySession").apply {
            setCallback(MediaSessionCallback())
            setPlaybackState(
                PlaybackState.Builder()
                    .setState(PlaybackState.STATE_PLAYING, 0, 1.0f)
                    .build(),
            )
            isActive = true
        }

        Log.d(TAG, "Volume key interception started (enabled=$enabled)")
    }

    private fun stop() {
        active = false
        enabled = false

        mediaSession?.apply {
            isActive = false
            release()
        }
        mediaSession = null

        Log.d(TAG, "Volume key interception stopped")
    }

    private inner class MediaSessionCallback : MediaSession.Callback() {
        override fun onMediaButtonEvent(event: android.content.Intent): Boolean {
            val keyEvent =
                event.getParcelableExtra<KeyEvent>(android.content.Intent.EXTRA_KEY_EVENT)
                    ?: return false

            if (keyEvent.action != KeyEvent.ACTION_DOWN) return true

            val key = when (keyEvent.keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
                KeyEvent.KEYCODE_VOLUME_UP -> "up"
                else -> null
            }

            if (key != null) {
                Log.d(TAG, "Volume key intercepted: $key (enabled=$enabled)")
                if (enabled) {
                    channel.invokeMethod("onVolumeKey", mapOf("key" to key))
                }
                return true
            }

            return super.onMediaButtonEvent(event)
        }
    }
}
