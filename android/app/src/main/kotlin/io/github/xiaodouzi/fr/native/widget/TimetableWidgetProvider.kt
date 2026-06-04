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
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 课表桌面小组件
 *
 * 渲染策略（XML 化版）：
 * - 扔掉 Canvas+Bitmap，直接用 XML 布局（LinearLayout + TextView + weight）
 * - 字号 / 单元格比例硬编码在 res/values/styles.xml 的 TimetableCell 样式中
 *   - 单元格宽 ≈ 38dp（5×4 widget），课程 textSize = 28sp → 单字宽 ≈ 28dp → 比例 0.74 ≈ 0.75
 * - 课程数据按"当前周"在 Dart 端预过滤后写入 SharedPreferences，Kotlin 仅做渲染
 * - 主 app 进程被杀后 widget 仍能显示：系统 30 分钟周期 + 用户点标题触发 ACTION_REFRESH
 */
class TimetableWidgetProvider : AppWidgetProvider() {

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
            val ids = mgr.getAppWidgetIds(
                ComponentName(context, TimetableWidgetProvider::class.java)
            )
            for (id in ids) updateAppWidget(context, mgr, id)
        }
    }

    companion object {
        const val ACTION_REFRESH = "io.github.xiaodouzi.fr.action.TIMETABLE_WIDGET_REFRESH"

        private const val MAX_DAYS = 7
        private const val MAX_SLOTS = 5

        // 莫兰迪色（与 Flutter 端 timetable_widget_colors.dart 保持一致）
        private val COURSE_PALETTE = intArrayOf(
            0xFF8B9DC3.toInt(), // 灰蓝
            0xFF9E8FA8.toInt(), // 灰紫
            0xFFB58AA5.toInt(), // 灰粉
            0xFFC49A8B.toInt(), // 灰橘
            0xFFA8C4A2.toInt(), // 灰绿
            0xFF7FAAAA.toInt(), // 灰青
            0xFFA5B5C4.toInt(), // 雾蓝
            0xFFC4B5A0.toInt()  // 灰棕
        )

        // 单元格资源 ID 表（35 个 cell_0_0 .. cell_4_6）
        private val CELL_IDS: Array<IntArray> = arrayOf(
            intArrayOf(
                R.id.cell_0_0, R.id.cell_0_1, R.id.cell_0_2, R.id.cell_0_3,
                R.id.cell_0_4, R.id.cell_0_5, R.id.cell_0_6
            ),
            intArrayOf(
                R.id.cell_1_0, R.id.cell_1_1, R.id.cell_1_2, R.id.cell_1_3,
                R.id.cell_1_4, R.id.cell_1_5, R.id.cell_1_6
            ),
            intArrayOf(
                R.id.cell_2_0, R.id.cell_2_1, R.id.cell_2_2, R.id.cell_2_3,
                R.id.cell_2_4, R.id.cell_2_5, R.id.cell_2_6
            ),
            intArrayOf(
                R.id.cell_3_0, R.id.cell_3_1, R.id.cell_3_2, R.id.cell_3_3,
                R.id.cell_3_4, R.id.cell_3_5, R.id.cell_3_6
            ),
            intArrayOf(
                R.id.cell_4_0, R.id.cell_4_1, R.id.cell_4_2, R.id.cell_4_3,
                R.id.cell_4_4, R.id.cell_4_5, R.id.cell_4_6
            )
        )

        private val DAY_IDS = intArrayOf(
            R.id.day_0, R.id.day_1, R.id.day_2, R.id.day_3,
            R.id.day_4, R.id.day_5, R.id.day_6
        )

        private val SLOT_IDS = intArrayOf(
            R.id.slot_0, R.id.slot_1, R.id.slot_2, R.id.slot_3, R.id.slot_4
        )

        // 透明（无课单元格不显示背景，靠 gap 形成网格线）
        private const val COLOR_EMPTY = 0
        // 蓝色（今天高亮）
        private const val COLOR_TODAY = 0xFF1976D2.toInt()
        // 极浅蓝灰（今天列的非当日单元格底色）
        private const val COLOR_TODAY_COL_BG = 0xFFF5F8FC.toInt()

        internal fun updateAppWidget(
            context: Context,
            mgr: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = HomeWidgetPlugin.getData(context)
            val jsonStr = prefs.getString("timetable_widget_json", null)

            val parsed = parseData(jsonStr)
            val todayDayOfCycle = computeTodayDayOfCycle(
                startDateIso = parsed.startDateIso,
                daysPerCycle = parsed.daysPerCycle
            )
            val weekNumber = computeCurrentWeekNumber(
                startDateIso = parsed.startDateIso,
                daysPerCycle = parsed.daysPerCycle
            )
            val titleText =
                if (weekNumber > 0) "课程表 · 第$weekNumber 周" else "课程表"

            val views = RemoteViews(context.packageName, R.layout.timetable_widget).apply {
                setTextViewText(R.id.timetable_title, titleText)

                // 1) 课程格子
                for (s in 0 until MAX_SLOTS) {
                    for (d in 0 until MAX_DAYS) {
                        val cellId = CELL_IDS[s][d]
                        val outOfRange = d >= parsed.daysPerCycle || s >= parsed.slotsPerDay
                        val cell = if (outOfRange) null
                        else parsed.cells.getOrNull(d * MAX_SLOTS + s)

                        if (cell == null) {
                            setTextViewText(cellId, "")
                            // 无课：浅灰；今天列的话用更浅的蓝灰
                            val bg = if (d == todayDayOfCycle) COLOR_TODAY_COL_BG
                            else COLOR_EMPTY
                            setInt(cellId, "setBackgroundColor", bg)
                        } else {
                            // 两行排版：课程名 + 地点（样式 TimetableCell 已设 maxLines=2）
                            val displayText = cell.displayText
                            setTextViewText(cellId, displayText)
                            setInt(cellId, "setBackgroundColor", cell.color)
                        }
                    }
                }

                // 2) 左侧节数（slotsPerDay 之外的灰掉）
                for (s in 0 until MAX_SLOTS) {
                    val outOfRange = s >= parsed.slotsPerDay
                    val color = if (outOfRange) 0xFFBDBDBD.toInt() else 0xFF374151.toInt()
                    setTextColor(SLOT_IDS[s], color)
                }

                // 3) 顶部星期（今天那列变蓝底白字）
                for (d in 0 until MAX_DAYS) {
                    if (d == todayDayOfCycle) {
                        setInt(DAY_IDS[d], "setBackgroundColor", COLOR_TODAY)
                        setTextColor(DAY_IDS[d], 0xFFFFFFFF.toInt())
                    } else {
                        setInt(DAY_IDS[d], "setBackgroundColor", 0)
                        setTextColor(DAY_IDS[d], 0xFF666666.toInt())
                    }
                }

                // 4) 标题栏：可点击触发 ACTION_REFRESH（兜底：app 进程被杀后仍能刷新）
                val refreshIntent = Intent(context, TimetableWidgetProvider::class.java).apply {
                    action = ACTION_REFRESH
                }
                val refreshPi = PendingIntent.getBroadcast(
                    context,
                    appWidgetId,
                    refreshIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.timetable_title, refreshPi)

                // 5) 主体点击：打开 app 到课表页
                val openIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = android.net.Uri.parse("fr://timetable")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                val openPi = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                setOnClickPendingIntent(R.id.timetable_container, openPi)
            }

            mgr.updateAppWidget(appWidgetId, views)
        }

        // ──────────────────── 数据解析 ────────────────────

        private data class Cell(
            val title: String,
            val location: String,
            val color: Int
        ) {
            /// 两行排版文本：课程名 \n 地点（无地点则只显示课程名）
            val displayText: String
                get() {
                    val loc = location.trim()
                    if (loc.isEmpty()) return title
                    return "$title\n$loc"
                }
        }

        private data class Parsed(
            val startDateIso: String,
            val daysPerCycle: Int,
            val slotsPerDay: Int,
            val cells: List<Cell?>
        )

        private fun parseData(jsonStr: String?): Parsed {
            val emptyCells = List<Cell?>(MAX_DAYS * MAX_SLOTS) { null }
            if (jsonStr.isNullOrBlank()) {
                return Parsed("1970-01-01", 0, 0, emptyCells)
            }
            return try {
                val obj = JSONObject(jsonStr)
                val startIso = obj.optString("startDateIso", "1970-01-01")
                val days = obj.optInt("daysPerCycle", 0).coerceIn(0, MAX_DAYS)
                val slots = obj.optInt("slotsPerDay", 0).coerceIn(0, MAX_SLOTS)
                val arr = obj.optJSONArray("cells") ?: org.json.JSONArray()

                val cells = mutableListOf<Cell?>()
                for (i in 0 until MAX_DAYS * MAX_SLOTS) {
                    if (i >= arr.length()) {
                        cells.add(null)
                        continue
                    }
                    val c = arr.optJSONObject(i) ?: continue
                    val title = c.optString("title", "")
                    if (title.isEmpty()) {
                        cells.add(null)
                        continue
                    }
                    val location = c.optString("location", "")
                    val colorHex = c.optString("color", "")
                    val colorInt = parseHexColor(colorHex) ?: 0xFF9E9E9E.toInt()
                    cells.add(Cell(title = title, location = location, color = colorInt))
                }

                Parsed(startIso, days, slots, cells)
            } catch (e: Throwable) {
                Parsed("1970-01-01", 0, 0, emptyCells)
            }
        }

        private fun parseHexColor(hex: String?): Int? {
            if (hex.isNullOrBlank()) return null
            val s = if (hex.startsWith("#")) hex else "#$hex"
            return try {
                android.graphics.Color.parseColor(s)
            } catch (_: Throwable) {
                null
            }
        }

        /**
         * 根据 startDateIso + daysPerCycle 计算今天在周期中的 dayOfCycle。
         * 超出 [startDate, ...) 返回 -1；daysPerCycle == 0 时返回 -1。
         */
        private fun computeTodayDayOfCycle(startDateIso: String, daysPerCycle: Int): Int {
            if (daysPerCycle <= 0) return -1
            val dayOffset = dayOffsetFromStart(startDateIso) ?: return -1
            if (dayOffset < 0) return -1
            return dayOffset % daysPerCycle
        }

        /**
         * 计算当前周次（1-based）。1 周 = 7 自然日，与 daysPerCycle 解耦，
         * 方便用户按"教学周"理解。
         */
        private fun computeCurrentWeekNumber(
            startDateIso: String,
            daysPerCycle: Int
        ): Int {
            if (daysPerCycle <= 0) return -1
            val dayOffset = dayOffsetFromStart(startDateIso) ?: return -1
            if (dayOffset < 0) return -1
            return (dayOffset / 7) + 1
        }

        private fun dayOffsetFromStart(startDateIso: String): Int? {
            return try {
                val sdf = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
                    timeZone = TimeZone.getDefault()
                    isLenient = false
                }
                val start = sdf.parse(startDateIso) ?: return null
                val today = java.util.Calendar.getInstance().apply {
                    time = Date()
                    set(java.util.Calendar.HOUR_OF_DAY, 0)
                    set(java.util.Calendar.MINUTE, 0)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                }.time
                val startCal = java.util.Calendar.getInstance().apply {
                    time = start
                    set(java.util.Calendar.HOUR_OF_DAY, 0)
                    set(java.util.Calendar.MINUTE, 0)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                }.time
                ((today.time - startCal.time) / (1000L * 60 * 60 * 24)).toInt()
            } catch (_: Throwable) {
                null
            }
        }
    }
}
