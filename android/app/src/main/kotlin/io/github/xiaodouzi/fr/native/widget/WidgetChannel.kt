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
                "navigateToClock" -> {
                    onNavigateToClock?.invoke()
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
                "navigateToRecorder" -> {
                    val autostart = call.argument<Boolean>("autostart") ?: true
                    onNavigateToRecorder?.invoke(autostart)
                    result.success(null)
                }
                "navigateToClockWidgetToggle" -> {
                    onNavigateToClockWidgetToggle?.invoke()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    var onNavigateToLab: (() -> Unit)? = null
    var onNavigateToCalendar: (() -> Unit)? = null
    var onNavigateToClock: (() -> Unit)? = null
    var onNavigateToTimetable: (() -> Unit)? = null

    /// Notion 图床页面跳转回调，[autocapture] = true 表示从桌面 widget 进入，
    /// 期望自动触发拍照。
    var onNavigateToNotionImage: ((Boolean) -> Unit)? = null

    /// 录音机页面跳转回调，[autostart] = true 表示从桌面 widget 进入，
    /// 期望自动开始录音。
    var onNavigateToRecorder: ((Boolean) -> Unit)? = null

    /// 时钟 toggle 按钮跳转回调（桌面 widget → app 内 toggle 最新 clock）。
    var onNavigateToClockWidgetToggle: (() -> Unit)? = null

    fun notifyNavigateToLab() {
        channel.invokeMethod("navigateToLab", null)
    }

    fun notifyNavigateToCalendar() {
        channel.invokeMethod("navigateToCalendar", null)
    }

    fun notifyNavigateToClock() {
        channel.invokeMethod("navigateToClock", null)
    }

    fun notifyNavigateToTimetable() {
        channel.invokeMethod("navigateToTimetable", null)
    }

    fun notifyNavigateToNotionImage(autocapture: Boolean) {
        channel.invokeMethod("navigateToNotionImage", autocapture)
    }

    fun notifyNavigateToRecorder(autostart: Boolean) {
        channel.invokeMethod("navigateToRecorder", autostart)
    }

    fun notifyNavigateToClockWidgetToggle() {
        channel.invokeMethod("navigateToClockWidgetToggle", null)
    }

    /// 通知 Flutter 收到外部分享（其他 app 分享文本/文件到 FR）。
    /// [text] 分享文本（可为 null），[fileUris] 分享文件 content:// URI 列表。
    fun notifyShareReceived(text: String?, fileUris: List<String>) {
        channel.invokeMethod(
            "shareReceived",
            mapOf("text" to text, "files" to fileUris),
        )
    }
}
