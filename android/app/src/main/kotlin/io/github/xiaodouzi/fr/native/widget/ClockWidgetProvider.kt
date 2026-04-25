package io.github.xiaodouzi.fr.native.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import io.github.xiaodouzi.fr.MainActivity
import io.github.xiaodouzi.fr.R

class ClockWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val widgetData = HomeWidgetPlugin.getData(context)

            val title = widgetData.getString("clock_title", "暂无倒计时")
            val formattedTime = widgetData.getString("clock_formatted_time", "00:00:00")
            val isRunning = widgetData.getString("clock_is_running", "0") == "1"
            val isOvertime = widgetData.getString("clock_is_overtime", "0") == "1"

            val (statusText, statusIcon, _) = when {
                isOvertime -> Triple("已超时", "🌙", "#FF5722")
                isRunning -> Triple("进行中", "☀️", "#4CAF50")
                else -> Triple("已暂停", "☁️", "#9E9E9E")
            }

            val views = RemoteViews(context.packageName, R.layout.clock_widget).apply {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_time, formattedTime)
                setTextViewText(R.id.widget_status, statusText)
                setTextViewText(R.id.widget_icon, statusIcon)

                val intent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = android.net.Uri.parse("fr://lab")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onEnabled(context: Context) {}
    override fun onDisabled(context: Context) {}
}
