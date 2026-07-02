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
                "navigateToNotionImage" -> {
                    val autocapture = call.argument<Boolean>("autocapture") ?: false
                    onNavigateToNotionImage?.invoke(autocapture)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    var onNavigateToLab: (() -> Unit)? = null
    var onNavigateToCalendar: (() -> Unit)? = null
    var onNavigateToTimetable: (() -> Unit)? = null

    /// Notion 图床页面跳转回调，[autocapture] = true 表示从桌面 widget 进入，
    /// 期望自动触发拍照。
    var onNavigateToNotionImage: ((Boolean) -> Unit)? = null

    fun notifyNavigateToLab() {
        channel.invokeMethod("navigateToLab", null)
    }

    fun notifyNavigateToCalendar() {
        channel.invokeMethod("navigateToCalendar", null)
    }

    fun notifyNavigateToTimetable() {
        channel.invokeMethod("navigateToTimetable", null)
    }

    fun notifyNavigateToNotionImage(autocapture: Boolean) {
        channel.invokeMethod("navigateToNotionImage", autocapture)
    }
}
