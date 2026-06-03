package io.github.xiaodouzi.fr.native.calendar

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// 系统日历 MethodChannel
///
/// 提供：权限检查/请求、插入日历事件
/// 使用 Android Calendar ContentProvider
class CalendarChannel(
    messenger: BinaryMessenger,
    private val activity: Activity
) {
    companion object {
        const val NAME = "io.github.xiaodouzi.fr/calendar"
        const val REQUEST_CODE = 2001
    }

    private val channel = MethodChannel(messenger, NAME).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPermission" -> {
                    result.success(hasPermission())
                }
                "requestPermission" -> {
                    requestPermission()
                    result.success(null)
                }
                "insertEvent" -> {
                    try {
                        val title = call.argument<String>("title") ?: ""
                        val description = call.argument<String>("description") ?: ""
                        val year = call.argument<Int>("year") ?: return@setMethodCallHandler result.error("BAD_ARGS", "year required", null)
                        val month = call.argument<Int>("month") ?: return@setMethodCallHandler result.error("BAD_ARGS", "month required", null)
                        val day = call.argument<Int>("day") ?: return@setMethodCallHandler result.error("BAD_ARGS", "day required", null)

                        if (!hasPermission()) {
                            result.error("NO_PERMISSION", "Calendar permission not granted", null)
                            return@setMethodCallHandler
                        }

                        val eventId = insertCalendarEvent(title, description, year, month, day)
                        if (eventId != null) {
                            result.success(eventId)
                        } else {
                            result.error("INSERT_FAILED", "Failed to insert calendar event", null)
                        }
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "deleteEvent" -> {
                    try {
                        val eventId = call.argument<Int>("eventId") ?: return@setMethodCallHandler result.error("BAD_ARGS", "eventId required", null)
                        val deleted = deleteCalendarEvent(eventId.toLong())
                        result.success(deleted)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasPermission(): Boolean {
        val read = ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_CALENDAR)
        val write = ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_CALENDAR)
        return read == PackageManager.PERMISSION_GRANTED && write == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission() {
        if (!hasPermission()) {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.READ_CALENDAR, Manifest.permission.WRITE_CALENDAR),
                REQUEST_CODE
            )
        }
    }

    /**
     * 插入日历事件到默认日历
     *
     * 使用全天事件（allDay=1），开始时间用 UTC 毫秒表示当天 0 点
     * 持续 1 天。这样在日历 app 中显示为"待办"标记
     */
    private fun insertCalendarEvent(title: String, description: String, year: Int, month: Int, day: Int): Long? {
        val cal = java.util.Calendar.getInstance().apply {
            set(java.util.Calendar.YEAR, year)
            set(java.util.Calendar.MONTH, month - 1) // Java Calendar: 0-based
            set(java.util.Calendar.DAY_OF_MONTH, day)
            set(java.util.Calendar.HOUR_OF_DAY, 0)
            set(java.util.Calendar.MINUTE, 0)
            set(java.util.Calendar.SECOND, 0)
            set(java.util.Calendar.MILLISECOND, 0)
        }
        val startMillis = cal.timeInMillis

        // 结束时间：+1天
        cal.add(java.util.Calendar.DAY_OF_MONTH, 1)
        val endMillis = cal.timeInMillis

        val values = ContentValues().apply {
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.DTSTART, startMillis)
            put(CalendarContract.Events.DTEND, endMillis)
            put(CalendarContract.Events.ALL_DAY, 1)
            put(CalendarContract.Events.CALENDAR_ID, getDefaultCalendarId())
            put(CalendarContract.Events.EVENT_TIMEZONE, java.util.TimeZone.getDefault().id)
        }

        val uri = activity.contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
        return uri?.lastPathSegment?.toLongOrNull()
    }

    /**
     * 获取默认日历 ID
     */
    private fun getDefaultCalendarId(): Long {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.IS_PRIMARY
        )

        activity.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            null,
            null,
            "${CalendarContract.Calendars.IS_PRIMARY} DESC"
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID))
            }
        }

        // 如果没有主日历，获取第一个可写日历
        activity.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            "${CalendarContract.Calendars.ACCOUNT_TYPE} != ?",
            arrayOf("com.google"),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID))
            }
        }

        // 最后 fallback：获取任意日历
        activity.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            null,
            null,
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID))
            }
        }

        return 1L // fallback
    }

    /**
     * 删除日历事件
     */
    private fun deleteCalendarEvent(eventId: Long): Int {
        val uri = CalendarContract.Events.CONTENT_URI.buildUpon()
            .appendPath(eventId.toString())
            .build()
        return activity.contentResolver.delete(uri, null, null)
    }
}
