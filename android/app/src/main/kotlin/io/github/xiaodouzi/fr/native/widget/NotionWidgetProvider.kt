package io.github.xiaodouzi.fr.native.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import io.github.xiaodouzi.fr.MainActivity
import io.github.xiaodouzi.fr.R

/**
 * Notion 图床桌面小组件
 *
 * 行为（全部走 deep link，**不**直接调系统相机 — Flutter 端 image_picker
 * 走原生相机并接 ActivityResult，体验更稳定）：
 *   - 整体或拍照按钮点击 → 启动 MainActivity，URI 携带 `?autocapture=1` 参数
 *   - Flutter main.dart 解析 URI，跳转 NotionImageHostPage
 *   - NotionImageHostPage initState 读 autocapture 标志，自动调 _capture()
 *
 * 不需要 SharedPreferences 数据（纯跳转型 widget），只接 onUpdate。
 */
class NotionWidgetProvider : AppWidgetProvider() {

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
        /// 自定义 action（保留以便未来扩展，如「仅打开不拍照」）
        const val ACTION_OPEN_WITH_CAPTURE =
            "io.github.xiaodouzi.fr.action.NOTION_WIDGET_CAPTURE"

        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.notion_widget).apply {
                // 整体点击：打开 Notion 图床页面 + 自动拍照
                val openIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    // deep link：fr://notionimg?autocapture=1
                    data = android.net.Uri.parse("fr://notionimg?autocapture=1")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val openPi = PendingIntent.getActivity(
                    context,
                    appWidgetId, // 每个 widget 实例独立 PendingIntent
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_root, openPi)
                // 拍照按钮点击：同样的行为（聚焦感更强）
                setOnClickPendingIntent(R.id.widget_capture_btn, openPi)
            }
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}