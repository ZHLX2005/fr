package com.example.flutter_application_1

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class ClockWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        // 遍历所有 widget 实例进行更新
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        // 更新 widget 的内部方法
        internal fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            // 从 HomeWidget 获取存储的时钟数据
            val widgetData = HomeWidgetPlugin.getData(context)

            val title = widgetData.getString("clock_title", "暂无倒计时")
            val formattedTime = widgetData.getString("clock_formatted_time", "00:00:00")
            val remainingSeconds = widgetData.getString("clock_remaining_seconds", "0")?.toIntOrNull() ?: 0
            val isRunning = widgetData.getString("clock_is_running", "0") == "1"
            val isOvertime = widgetData.getString("clock_is_overtime", "0") == "1"
            val colorHex = widgetData.getString("clock_color", "#2196F3")

            // 解析颜色
            val textColor = try {
                Color.parseColor(colorHex ?: "#2196F3")
            } catch (e: Exception) {
                Color.WHITE
            }

            // 根据超时状态设置背景颜色
            val bgColor = if (isOvertime) {
                // 超时：红色系
                Color.parseColor("#FF5722")
            } else if (isRunning) {
                // 运行中：使用主题色
                try {
                    Color.parseColor(colorHex ?: "#2196F3")
                } catch (e: Exception) {
                    Color.parseColor("#2196F3")
                }
            } else {
                // 暂停/未运行：灰色
                Color.parseColor("#757575")
            }

            // 构建 RemoteViews
            val views = RemoteViews(context.packageName, R.layout.clock_widget).apply {
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_time, formattedTime)
                setTextViewText(R.id.widget_status, when {
                    isOvertime -> "已超时"
                    isRunning -> "进行中"
                    else -> "已暂停"
                })

                // 设置颜色
                setTextColor(R.id.widget_time, Color.WHITE)
                setTextColor(R.id.widget_title, Color.WHITE)
                setTextColor(R.id.widget_status, Color.WHITE)
            }

            // 更新 widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onEnabled(context: Context) {
        // 首次创建 widget 时调用
    }

    override fun onDisabled(context: Context) {
        // 最后一个 widget 被删除时调用
    }
}
