package io.github.xiaodouzi.fr.native.liquid

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object LiquidGlassChannel {
    const val NAME = "com.xiaodouzi.fr/liquid_glass"

    fun register(messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, NAME)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    val supported = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S
                    result.success(supported)
                }
                else -> result.notImplemented()
            }
        }
    }
}
