package io.github.xiaodouzi.fr.native.crash

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class CrashLogChannel(messenger: BinaryMessenger, private val context: Context) {
    companion object {
        const val NAME = "io.github.xiaodouzi.fr/crash"
    }

    private val channel = MethodChannel(messenger, NAME)

    fun setMethodCallHandler() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCrashLogs" -> {
                    val logs = CrashLogHandler.getCrashLogs(context)
                    result.success(logs)
                }
                "clearCrashLogs" -> {
                    CrashLogHandler.clearCrashLogs(context)
                    result.success(true)
                }
                "hasCrashLog" -> {
                    result.success(CrashLogHandler.hasCrashLog(context))
                }
                else -> result.notImplemented()
            }
        }
    }
}
