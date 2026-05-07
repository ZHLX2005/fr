package io.github.xiaodouzi.fr.native.crash

import android.content.Context
import android.os.Build
import java.io.File
import java.io.FileWriter
import java.io.PrintWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class CrashLogHandler private constructor(
    private val context: Context,
    private val defaultHandler: Thread.UncaughtExceptionHandler?
) : Thread.UncaughtExceptionHandler {

    companion object {
        private const val CRASH_DIR = "crash_logs"
        private const val MAX_LOGS = 5

        @Volatile
        private var instance: CrashLogHandler? = null

        fun init(context: Context) {
            if (instance != null) return
            val default = Thread.getDefaultUncaughtExceptionHandler()
            instance = CrashLogHandler(context.applicationContext, default)
            Thread.setDefaultUncaughtExceptionHandler(instance)
        }

        fun getCrashLogs(context: Context): List<Map<String, String>> {
            val dir = File(context.filesDir, CRASH_DIR)
            if (!dir.exists()) return emptyList()
            return dir.listFiles()
                ?.filter { it.name.endsWith(".txt") }
                ?.sortedByDescending { it.name }
                ?.take(MAX_LOGS)
                ?.map { mapOf("time" to it.nameWithoutExtension, "content" to it.readText()) }
                ?: emptyList()
        }

        fun clearCrashLogs(context: Context) {
            val dir = File(context.filesDir, CRASH_DIR)
            dir.listFiles()?.forEach { it.delete() }
        }

        fun hasCrashLog(context: Context): Boolean {
            val dir = File(context.filesDir, CRASH_DIR)
            return dir.exists() && dir.listFiles()?.isNotEmpty() == true
        }
    }

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        saveCrashLog(thread, throwable)
        defaultHandler?.uncaughtException(thread, throwable)
    }

    private fun saveCrashLog(thread: Thread, throwable: Throwable) {
        try {
            val dir = File(context.filesDir, CRASH_DIR)
            if (!dir.exists()) dir.mkdirs()

            // 清理旧日志
            dir.listFiles()
                ?.filter { it.name.endsWith(".txt") }
                ?.sortedBy { it.lastModified() }
                ?.dropLast(MAX_LOGS - 1)
                ?.forEach { it.delete() }

            val timestamp = SimpleDateFormat("yyyy-MM-dd_HH-mm-ss", Locale.getDefault()).format(Date())
            val file = File(dir, "$timestamp.txt")

            PrintWriter(FileWriter(file)).use { pw ->
                pw.println("Time: $timestamp")
                pw.println("Thread: ${thread.name}")
                pw.println("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
                pw.println("Android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})")
                pw.println("App: ${context.packageName}")
                pw.println("---")
                throwable.printStackTrace(pw)
            }
        } catch (e: Exception) {
            // 写日志失败不应阻止崩溃流程
        }
    }
}
