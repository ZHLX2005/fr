package io.github.xiaodouzi.fr.native.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.view.View
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

        // prefs key —— 只保留这里真正会读的，与 Dart 侧
        // lib/native/home_widget/clock_widget_service.dart 的写入集合一一对应。
        // 新增 key 必须两边同时改，否则是静默失效。
        private const val KEY_TITLE = "clock_title"
        private const val KEY_IS_RUNNING = "clock_is_running"
        private const val KEY_IS_PAUSED_AT_START = "clock_is_paused_at_start"
        private const val KEY_REMAINING_SECONDS = "clock_remaining_seconds"
        private const val KEY_START_TIME_MS = "clock_start_time_ms"
        private const val KEY_START_REMAINING_SECONDS = "clock_start_remaining_seconds"

        /** 锚点可信区间：±30 天。超出即认为 prefs 数据不可信，退回静态文本。 */
        private const val MAX_TRUSTED_REMAINING_MS = 30L * 24 * 60 * 60 * 1000

        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val widgetData = HomeWidgetPlugin.getData(context)

            val title = widgetData.getString(KEY_TITLE, "暂无倒计时") ?: "暂无倒计时"
            val isRunning = widgetData.getString(KEY_IS_RUNNING, "0") == "1"
            val savedRemaining =
                widgetData.getString(KEY_REMAINING_SECONDS, "0")?.toIntOrNull() ?: 0
            val startTimeMs =
                widgetData.getString(KEY_START_TIME_MS, "0")?.toLongOrNull() ?: 0L
            val startRemaining =
                widgetData.getString(KEY_START_REMAINING_SECONDS, "0")?.toIntOrNull()
                    ?: savedRemaining

            // 实时计算 remaining（**毫秒精度**，不要先 /1000 取整 —— 否则每次
            // 推送都会引入最多 1 秒的固定偏差）：如果在跑且有合法 startTime，
            // 按当前时间推算，否则退回到 Flutter 端最后保存的快照值。
            // 这样即使 Flutter 进程被杀，widget 下次刷新仍能显示正确时间。
            val remainingMs: Long = if (isRunning && startTimeMs > 0L) {
                startRemaining * 1000L - (System.currentTimeMillis() - startTimeMs)
            } else {
                savedRemaining * 1000L
            }

            val isOvertime = remainingMs < 0L

            // ── 走字交给 Chronometer，app 侧不再每秒推送 ──────────────────
            //
            // base 是"从现在起还要数多少"，锚在 SystemClock.elapsedRealtime()
            // （**含深睡眠**，不能用 uptimeMillis，否则息屏时会停住）。
            // base 是绝对锚点，与 host 何时 apply 无关，所以不需要持久化，
            // 每次 update 重算即可。
            //
            // 脏数据兜底：remaining 超出 ±30 天说明 prefs 里的锚点不可信
            // （陈旧值 / 手工改系统时间），退回静态文本，避免 Chronometer
            // 渲染出天文数字。
            val anchorTrustworthy = abs(remainingMs) < MAX_TRUSTED_REMAINING_MS
            val useChronometer = isRunning && startTimeMs > 0L && anchorTrustworthy
            val base = SystemClock.elapsedRealtime() + remainingMs

            // 静态分支显示 Flutter 端最后落盘的快照值（暂停态的实际剩余就是它）
            val formattedTime = formatHms(savedRemaining)

            // border-emphasis：状态 pill 用"浅 tint 底 drawable + 同色描边 + 同色字/图标"，
            // tint/描边在 drawable 里，这里只下发本色。图标用 vector（去 emoji）。
            data class StatusStyle(val text: String, val iconRes: Int, val pillRes: Int, val color: Int)

            val isPausedAtStart = widgetData.getString(KEY_IS_PAUSED_AT_START, "0") == "1"
            val style = when {
                isOvertime -> StatusStyle("已超时", R.drawable.widget_ic_overtime, R.drawable.status_pill_overtime, 0xFFE64A19.toInt())
                isRunning -> StatusStyle("进行中", R.drawable.widget_ic_running, R.drawable.status_pill_running, 0xFF4CAF50.toInt())
                isPausedAtStart -> StatusStyle("等待开始", R.drawable.widget_ic_idle, R.drawable.status_pill_idle, 0xFF2196F3.toInt())
                else -> StatusStyle("已暂停", R.drawable.widget_ic_paused, R.drawable.status_pill_paused, 0xFF757575.toInt())
            }

            val views = RemoteViews(context.packageName, R.layout.clock_widget).apply {
                setTextViewText(R.id.widget_title, title)

                if (useChronometer) {
                    // 顺序要紧：setChronometerCountDown 必须早于 setChronometer ——
                    // 后者内部 setBase() 会立刻 updateText()，而 updateText 读 mCountDown；
                    // 若那时还没落，第一帧会按"向上计数"把 base（未来时刻）减出天文数字。
                    // 同一批 action 应用完才绘制，所以顺序排对零成本。
                    //
                    // 全程 countDown=true 即可覆盖超时：Chronometer 数到 0 **不会自停**，
                    // 越过 0 后框架自动取绝对值并套 R.string.negative_duration（`-%s`）
                    // 渲染出负号。**不要**再 setFormat("-%s")，那会变成 `--00:12`。
                    setChronometerCountDown(R.id.widget_time_chrono, true)
                    setChronometer(R.id.widget_time_chrono, base, null, true)
                    setViewVisibility(R.id.widget_time_chrono, View.VISIBLE)
                    setViewVisibility(R.id.widget_time, View.GONE)
                } else {
                    // 显式 stop + 重下 base，避免 host 里残留上一轮的 1Hz ticker / 陈旧锚点
                    setChronometer(R.id.widget_time_chrono, base, null, false)
                    setViewVisibility(R.id.widget_time_chrono, View.GONE)
                    setViewVisibility(R.id.widget_time, View.VISIBLE)
                    setTextViewText(R.id.widget_time, formattedTime)
                }

                setTextViewText(R.id.widget_status, style.text)
                setTextColor(R.id.widget_status, style.color)
                // RemoteViews 没有 setBackgroundResource(id,res)，用 setInt 反射调用
                // View.setBackgroundResource(int) 来切换状态 pill 的 drawable
                setInt(R.id.widget_status, "setBackgroundResource", style.pillRes)
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

                // 新增：toggle 按钮 PendingIntent → fr://clock/widget-toggle
                // requestCode 用 appWidgetId + 1000 避开主体 (0) 与刷新图标 (appWidgetId)
                val toggleIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = android.net.Uri.parse("fr://clock/widget-toggle")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val togglePi = PendingIntent.getActivity(
                    context,
                    appWidgetId + 1000,
                    toggleIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.widget_toggle_btn, togglePi)

                // toggle 按钮图标按状态切换：运行中→暂停图标，否则→播放图标（点击即开始/继续）
                val toggleIconRes = if (isRunning) R.drawable.widget_ic_paused else R.drawable.widget_ic_play
                setImageViewResource(R.id.widget_toggle_btn, toggleIconRes)
                setColorInt(R.id.widget_toggle_btn, "setColorFilter", style.color, style.color)
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
