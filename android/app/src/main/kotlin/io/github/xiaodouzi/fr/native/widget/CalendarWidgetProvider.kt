package io.github.xiaodouzi.fr.native.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import io.github.xiaodouzi.fr.MainActivity
import io.github.xiaodouzi.fr.R
import org.json.JSONObject
import java.util.Calendar

/**
 * 日历桌面小组件
 *
 * 设计要点：
 * - 整个日历用 Canvas 绘制到一张 Bitmap，再 setImageViewBitmap 给 RemoteViews
 *   （RemoteViews 自由度有限，整图方案最灵活也最省 view 数量）
 * - 每天是一个圆；当天有事件则圆周用多色等弧标记；今天加粗边框高亮
 */
class CalendarWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) updateAppWidget(context, appWidgetManager, id)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, CalendarWidgetProvider::class.java))
            for (id in ids) updateAppWidget(context, mgr, id)
        }
    }

    companion object {
        const val ACTION_REFRESH = "io.github.xiaodouzi.fr.action.CALENDAR_WIDGET_REFRESH"

        private const val BITMAP_W = 720
        private const val BITMAP_H = 540

        internal fun updateAppWidget(
            context: Context,
            mgr: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = HomeWidgetPlugin.getData(context)

            // 视图年月（Flutter 端写入）
            val now = Calendar.getInstance()
            val viewYear = prefs.getString("calendar_year", null)?.toIntOrNull() ?: now.get(Calendar.YEAR)
            val viewMonth = prefs.getString("calendar_month", null)?.toIntOrNull() ?: (now.get(Calendar.MONTH) + 1)

            val todayYear = prefs.getString("calendar_today_year", null)?.toIntOrNull() ?: now.get(Calendar.YEAR)
            val todayMonth = prefs.getString("calendar_today_month", null)?.toIntOrNull() ?: (now.get(Calendar.MONTH) + 1)
            val todayDay = prefs.getString("calendar_today_day", null)?.toIntOrNull() ?: now.get(Calendar.DAY_OF_MONTH)

            // 每天颜色 map
            val colorsByDay = parseColorsByDay(prefs.getString("calendar_colors_json", "{}") ?: "{}")

            val bitmap = renderCalendar(
                viewYear = viewYear,
                viewMonth = viewMonth,
                todayYear = todayYear,
                todayMonth = todayMonth,
                todayDay = todayDay,
                colorsByDay = colorsByDay
            )

            val views = RemoteViews(context.packageName, R.layout.calendar_widget).apply {
                setTextViewText(R.id.calendar_title, "${viewYear}年${viewMonth}月")
                setImageViewBitmap(R.id.calendar_image, bitmap)

                // 主体点击：打开 app 到 /lab
                val openIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = android.net.Uri.parse("fr://lab")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val openPi = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.calendar_container, openPi)

                // 标题点击：仅刷新（基于 SharedPreferences 重画）
                val refreshIntent = Intent(context, CalendarWidgetProvider::class.java).apply {
                    action = ACTION_REFRESH
                }
                val refreshPi = PendingIntent.getBroadcast(
                    context,
                    appWidgetId,
                    refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.calendar_title, refreshPi)
            }

            mgr.updateAppWidget(appWidgetId, views)
        }

        private fun parseColorsByDay(jsonStr: String): Map<Int, List<Int>> {
            val out = HashMap<Int, List<Int>>()
            try {
                val obj = JSONObject(jsonStr)
                val keys = obj.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    val day = k.toIntOrNull() ?: continue
                    val arr = obj.optJSONArray(k) ?: continue
                    val colors = ArrayList<Int>(arr.length())
                    for (i in 0 until arr.length()) {
                        val hex = arr.optString(i)
                        val c = parseHexColor(hex) ?: continue
                        colors.add(c)
                    }
                    if (colors.isNotEmpty()) out[day] = colors
                }
            } catch (_: Throwable) {
                // 忽略坏数据
            }
            return out
        }

        private fun parseHexColor(hex: String?): Int? {
            if (hex.isNullOrBlank()) return null
            val s = if (hex.startsWith("#")) hex else "#$hex"
            return try { Color.parseColor(s) } catch (_: Throwable) { null }
        }

        /**
         * 绘制当月日历到 Bitmap
         */
        private fun renderCalendar(
            viewYear: Int,
            viewMonth: Int,
            todayYear: Int,
            todayMonth: Int,
            todayDay: Int,
            colorsByDay: Map<Int, List<Int>>
        ): Bitmap {
            val bmp = Bitmap.createBitmap(BITMAP_W, BITMAP_H, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            canvas.drawColor(Color.TRANSPARENT)

            val paint = Paint(Paint.ANTI_ALIAS_FLAG)

            // ── 布局参数 ─────────────────────────────────────
            val padLeft = 24f
            val padRight = 24f
            val headerHeight = 56f                 // 周几标题行
            val gridTop = headerHeight + 8f
            val gridLeft = padLeft
            val gridRight = BITMAP_W - padRight
            val gridBottom = BITMAP_H - 16f
            val cellW = (gridRight - gridLeft) / 7f
            val cellH = (gridBottom - gridTop) / 6f
            val radius = minOf(cellW, cellH) * 0.36f
            val ringStroke = radius * 0.22f

            // ── 周几标题（日 一 二 三 四 五 六） ─────────────
            val weekdays = arrayOf("日", "一", "二", "三", "四", "五", "六")
            paint.color = Color.parseColor("#999999")
            paint.textSize = 28f
            paint.textAlign = Paint.Align.CENTER
            paint.isFakeBoldText = false
            for (i in 0..6) {
                val cx = gridLeft + cellW * (i + 0.5f)
                val cy = headerHeight * 0.6f
                canvas.drawText(weekdays[i], cx, cy, paint)
            }

            // ── 计算当月起始位置 ───────────────────────────
            val cal = Calendar.getInstance().apply {
                clear()
                set(viewYear, viewMonth - 1, 1)
            }
            // Calendar.SUNDAY = 1
            val firstDow = cal.get(Calendar.DAY_OF_WEEK) - 1 // 0..6 对应 周日..周六
            val daysInMonth = cal.getActualMaximum(Calendar.DAY_OF_MONTH)

            // 上月天数（用于淡色填充）
            val prevCal = Calendar.getInstance().apply {
                clear()
                set(viewYear, viewMonth - 1, 1)
                add(Calendar.MONTH, -1)
            }
            val daysInPrev = prevCal.getActualMaximum(Calendar.DAY_OF_MONTH)

            // ── 绘制 6 × 7 网格 ────────────────────────────
            val numberPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textAlign = Paint.Align.CENTER
                textSize = radius * 0.95f
            }
            val ringBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = ringStroke
                color = Color.parseColor("#E0E0E0")
            }
            val ringFgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.STROKE
                strokeWidth = ringStroke
                strokeCap = Paint.Cap.BUTT
            }
            val todayBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                style = Paint.Style.FILL
                color = Color.parseColor("#1976D2")
            }

            val isViewMonthToday =
                viewYear == todayYear && viewMonth == todayMonth

            for (row in 0 until 6) {
                for (col in 0 until 7) {
                    val cellIdx = row * 7 + col
                    val cx = gridLeft + cellW * (col + 0.5f)
                    val cy = gridTop + cellH * (row + 0.5f)
                    val rectArc = RectF(cx - radius, cy - radius, cx + radius, cy + radius)

                    val displayDay: Int
                    val isInCurrentMonth: Boolean
                    when {
                        cellIdx < firstDow -> {
                            displayDay = daysInPrev - (firstDow - cellIdx - 1)
                            isInCurrentMonth = false
                        }
                        cellIdx >= firstDow + daysInMonth -> {
                            displayDay = cellIdx - firstDow - daysInMonth + 1
                            isInCurrentMonth = false
                        }
                        else -> {
                            displayDay = cellIdx - firstDow + 1
                            isInCurrentMonth = true
                        }
                    }

                    val isToday = isViewMonthToday && isInCurrentMonth && displayDay == todayDay

                    // 1) 今天底色填充（其他日子背景透明）
                    if (isToday) {
                        canvas.drawCircle(cx, cy, radius, todayBgPaint)
                    }

                    // 2) 圆环：本月才画背景灰环
                    if (isInCurrentMonth && !isToday) {
                        canvas.drawCircle(cx, cy, radius, ringBgPaint)
                    }

                    // 3) 当天事件颜色：等分弧
                    if (isInCurrentMonth) {
                        val colors = colorsByDay[displayDay]
                        if (!colors.isNullOrEmpty()) {
                            val sweep = 360f / colors.size
                            val gap = if (colors.size > 1) 4f else 0f
                            for ((i, c) in colors.withIndex()) {
                                ringFgPaint.color = c
                                val start = -90f + sweep * i + gap / 2f
                                canvas.drawArc(rectArc, start, sweep - gap, false, ringFgPaint)
                            }
                        }
                    }

                    // 4) 日期数字
                    numberPaint.color = when {
                        isToday -> Color.WHITE
                        !isInCurrentMonth -> Color.parseColor("#BDBDBD")
                        col == 0 || col == 6 -> Color.parseColor("#E53935") // 周末微红
                        else -> Color.parseColor("#212121")
                    }
                    val baseline = cy - (numberPaint.descent() + numberPaint.ascent()) / 2f
                    canvas.drawText(displayDay.toString(), cx, baseline, numberPaint)
                }
            }

            return bmp
        }
    }
}
