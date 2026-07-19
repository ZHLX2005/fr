package io.github.xiaodouzi.fr.native.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import io.github.xiaodouzi.fr.MainActivity
import io.github.xiaodouzi.fr.R
import kotlin.math.abs

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

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // 兜底刷新按钮：Flutter 进程死亡时，用户也能强制让 widget 基于 startTimeMs 重算最新时间
        if (intent.action == ACTION_REFRESH) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, ClockWidgetProvider::class.java))
            for (id in ids) {
                updateAppWidget(context, mgr, id)
            }
        }
    }

    companion object {
        const val ACTION_REFRESH = "io.github.xiaodouzi.fr.action.CLOCK_WIDGET_REFRESH"

        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val widgetData = HomeWidgetPlugin.getData(context)

            val title = widgetData.getString("clock_title", "暂无倒计时") ?: "暂无倒计时"
            val isRunning = widgetData.getString("clock_is_running", "0") == "1"
            val savedRemaining =
                widgetData.getString("clock_remaining_seconds", "0")?.toIntOrNull() ?: 0
            val startTimeMs =
                widgetData.getString("clock_start_time_ms", "0")?.toLongOrNull() ?: 0L
            val startRemaining =
                widgetData.getString("clock_start_remaining_seconds", "0")?.toIntOrNull()
                    ?: savedRemaining

            // 实时计算 remaining：如果在跑且有合法 startTime，按当前时间推算，
            // 否则退回到 Flutter 端最后保存的快照值。
            // 这样即使 Flutter 进程被杀，widget 下次刷新仍能显示正确时间。
            val remaining = if (isRunning && startTimeMs > 0) {
                val elapsedSec = (System.currentTimeMillis() - startTimeMs) / 1000
                (startRemaining - elapsedSec).toInt()
            } else {
                savedRemaining
            }

            val isOvertime = remaining < 0
            val formattedTime = formatHms(remaining)

            // border-emphasis：状态 pill 用"浅 tint 底 drawable + 同色描边 + 同色字/图标"，
            // tint/描边在 drawable 里，这里只下发本色。图标用 vector（去 emoji）。
            data class StatusStyle(val text: String, val iconRes: Int, val pillRes: Int, val color: Int)

            val style = when {
                isOvertime -> StatusStyle("已超时", R.drawable.widget_ic_overtime, R.drawable.status_pill_overtime, 0xFFE64A19.toInt())
                isRunning -> StatusStyle("进行中", R.drawable.widget_ic_running, R.drawable.status_pill_running, 0xFF4CAF50.toInt())
                else -> StatusStyle("已暂停", R.drawable.widget_ic_paused, R.drawable.status_pill_paused, 0xFF757575.toInt())
            }

            val views = RemoteViews(context.packageName, R.layout.clock_widget).apply {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_time, formattedTime)
                setTextViewText(R.id.widget_status, style.text)
                setTextColor(R.id.widget_status, style.color)
                setBackgroundResource(R.id.widget_status, style.pillRes)
                setImageViewResource(R.id.widget_icon, style.iconRes)
                setColorInt(R.id.widget_icon, "setColorFilter", style.color, style.color)

                // 主体点击：直达 ClockDemo 页面（fr://lab/demo/clock 走 frRouter 命中 LabDemoHandler）
                // 不再进入 Lab 首页，避免一次额外跳转。
                val intent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = android.net.Uri.parse("fr://lab/demo/clock")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_container, pendingIntent)

                // 右上角图标兼做刷新按钮：仅本地重算，不打开 app
                // （用 appWidgetId 做 requestCode 区分多 widget 实例）
                val refreshIntent = Intent(context, ClockWidgetProvider::class.java).apply {
                    action = ACTION_REFRESH
                }
                val refreshPi = PendingIntent.getBroadcast(
                    context,
                    appWidgetId,
                    refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_icon, refreshPi)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun formatHms(remainingSeconds: Int): String {
            val isOvertime = remainingSeconds < 0
            val abs = abs(remainingSeconds)
            val h = abs / 3600
            val m = (abs % 3600) / 60
            val s = abs % 60
            val sign = if (isOvertime) "-" else ""
            return "$sign${pad(h)}:${pad(m)}:${pad(s)}"
        }

        private fun pad(v: Int): String = if (v < 10) "0$v" else v.toString()
    }

    override fun onEnabled(context: Context) {}
    override fun onDisabled(context: Context) {}
}
