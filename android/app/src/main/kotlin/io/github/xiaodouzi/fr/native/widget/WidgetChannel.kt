package io.github.xiaodouzi.fr.native.widget

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// Widget -> Flutter 导航通道
class WidgetChannel(messenger: BinaryMessenger) {
    companion object {
        const val NAME = "io.github.xiaodouzi.fr/widget"
    }

    private val channel = MethodChannel(messenger, NAME).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "navigateToLab" -> {
                    onNavigateToLab?.invoke()
                    result.success(null)
                }
                "navigateToCalendar" -> {
                    onNavigateToCalendar?.invoke()
                    result.success(null)
                }
                "navigateToTimetable" -> {
                    onNavigateToTimetable?.invoke()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    var onNavigateToLab: (() -> Unit)? = null
    var onNavigateToCalendar: (() -> Unit)? = null
    var onNavigateToTimetable: (() -> Unit)? = null

    fun notifyNavigateToLab() {
        channel.invokeMethod("navigateToLab", null)
    }

    fun notifyNavigateToCalendar() {
        channel.invokeMethod("navigateToCalendar", null)
    }

    fun notifyNavigateToTimetable() {
        channel.invokeMethod("navigateToTimetable", null)
    }
}
