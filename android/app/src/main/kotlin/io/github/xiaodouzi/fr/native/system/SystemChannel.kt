package io.github.xiaodouzi.fr.native.system

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

/// 系统功能 MethodChannel
class SystemChannel(messenger: BinaryMessenger, private val activity: Activity) {
    companion object {
        const val NAME = "io.github.xiaodouzi.fr/system"
    }

    private val channel = MethodChannel(messenger, NAME).apply {
        setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsagePermission" -> {
                    result.success(checkUsagePermission())
                }
                "openUsageSettings" -> {
                    openUsageSettings()
                    result.success(null)
                }
                "queryAppUsage" -> {
                    result.success(queryAppUsage())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun checkUsagePermission(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    activity.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    activity.packageName
                )
            }
            return mode == AppOpsManager.MODE_ALLOWED
        }
        return false
    }

    private fun openUsageSettings() {
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
        activity.startActivity(intent)
    }

    private fun queryAppUsage(): List<Map<String, Any>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return emptyList()
        if (!checkUsagePermission()) return emptyList()

        val usageStatsManager = activity.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager

        val calendar = Calendar.getInstance()
        calendar.set(Calendar.HOUR_OF_DAY, 0)
        calendar.set(Calendar.MINUTE, 0)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        val startTime = calendar.timeInMillis
        val endTime = System.currentTimeMillis()

        val usageStatsList = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            startTime,
            endTime
        )

        val packageManager = activity.packageManager
        val result = mutableListOf<Map<String, Any>>()

        for (usageStats in usageStatsList) {
            if (usageStats.totalTimeInForeground > 0) {
                val appName = try {
                    val appInfo = packageManager.getApplicationInfo(usageStats.packageName, 0)
                    packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: Exception) {
                    usageStats.packageName
                }

                result.add(mapOf(
                    "packageName" to usageStats.packageName,
                    "appName" to appName,
                    "totalTimeInForeground" to usageStats.totalTimeInForeground,
                    "lastTimeUsed" to usageStats.lastTimeUsed
                ))
            }
        }

        return result.sortedByDescending { it["totalTimeInForeground"] as Long }
    }
}
