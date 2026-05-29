package io.github.xiaodouzi.fr.native.novel

import android.util.Log
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class NovelVolumeKeyChannel(
    messenger: BinaryMessenger,
) {
    companion object {
        private const val TAG = "NovelVolumeKeyChannel"
        const val NAME = "lab.novel_reader.volume_key_turn"
    }

    private val channel = MethodChannel(messenger, NAME)
    private var active = false
    var enabled = false
        private set

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setActive" -> {
                    active = call.arguments as? Boolean ?: false
                    if (!active) enabled = false
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

    /** Call from Activity.onKeyDown. Returns true if the key was consumed. */
    fun handleKeyEvent(keyCode: Int, event: KeyEvent?): Boolean {
        if (!active || event?.action != KeyEvent.ACTION_DOWN) return false

        val key = when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> "down"
            KeyEvent.KEYCODE_VOLUME_UP -> "up"
            else -> null
        } ?: return false

        Log.d(TAG, "Volume key intercepted: $key (enabled=$enabled)")

        if (enabled) {
            channel.invokeMethod("onVolumeKey", mapOf("key" to key))
        }
        // Always consume the event while active so system volume doesn't change
        return true
    }
}
