package io.github.xiaodouzi.fr.native.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import io.github.xiaodouzi.fr.MainActivity
import io.github.xiaodouzi.fr.R

/**
 * 录音机桌面小组件（v1）
 *
 * 行为：
 *   - 整体或录音按钮点击 → 启动 MainActivity，URI 携带 `?autostart=true` 参数
 *   - Flutter main.dart 解析 URI → FrNavigator → RecorderHandler
 *   - RecorderHandler 读 query[autostart] → markRecorderAutoStart()
 *   - RecorderDemoPage mount 后 consumeRecorderAutoStart() → controller.start()
 *
 * 不需要 SharedPreferences 数据（纯跳转型 widget），只接 onUpdate。
 *
 * 录音权限控制太难，所以 v1 采用"点击后进入页面再申请权限"的策略：
 * 用户在 app 内看到权限弹窗，比桌面弹窗体验更可控。
 */
class RecorderWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, id)
        }
    }

    companion object {
        /// 自定义 action（保留以便未来扩展，如"停止桌面录音"）
        const val ACTION_OPEN_WITH_RECORD =
            "io.github.xiaodouzi.fr.action.RECORDER_WIDGET_RECORD"

        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.recorder_widget).apply {
                // 整体点击：打开录音页面 + 自动开始录音
                val openIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    // deep link: fr://lab/demo/recorder?autostart=true
                    data = android.net.Uri.parse("fr://lab/demo/recorder?autostart=true")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val openPi = PendingIntent.getActivity(
                    context,
                    appWidgetId, // 每个 widget 实例独立 PendingIntent
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_root, openPi)
                // 录音按钮点击：同样的行为（聚焦感更强）
                setOnClickPendingIntent(R.id.widget_record_btn, openPi)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}