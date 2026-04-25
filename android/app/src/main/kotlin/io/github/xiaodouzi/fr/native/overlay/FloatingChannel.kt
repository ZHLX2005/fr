package io.github.xiaodouzi.fr.native.overlay

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// 悬浮窗 MethodChannel
class FloatingChannel(messenger: BinaryMessenger, private val context: Context) {
    companion object {
        const val NAME = "io.github.xiaodouzi.fr/floating"
    }

    private val channel = MethodChannel(messenger, NAME)

    var onScreenshotPermissionGranted: (() -> Unit)? = null
    var onScreenshotPermissionDenied: (() -> Unit)? = null
    var onRegionCaptured: ((ByteArray) -> Unit)? = null
    var onAiQuestion: ((String, String) -> Unit)? = null

    fun setMethodCallHandler() {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "checkOverlayPermission" -> {
                    result.success(FloatingWindowManager.canDrawOverlays(context))
                }
                "loadAiConfig" -> {
                    val prefs = context.getSharedPreferences("ai_config", Context.MODE_PRIVATE)
                    val defaultApiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
                    val defaultModel = "glm-4v-flash"
                    val defaultSystemPrompt = "你是一个专业的AI助手，请根据图片回答用户问题。"
                    result.success(mapOf(
                        "apiUrl" to (prefs.getString("api_url", null) ?: defaultApiUrl),
                        "apiKey" to (prefs.getString("api_key", null) ?: ""),
                        "model" to (prefs.getString("model", null) ?: defaultModel),
                        "systemPrompt" to (prefs.getString("system_prompt", null) ?: defaultSystemPrompt),
                        "directScreenshot" to (prefs.getBoolean("direct_screenshot", false))
                    ))
                }
                "requestOverlayPermission" -> {
                    val intent = FloatingWindowManager.getOverlaySettingsIntent(context)
                    context.startActivity(intent)
                    result.success(true)
                }
                "startFloating" -> {
                    if (!FloatingWindowManager.canDrawOverlays(context)) {
                        val intent = FloatingWindowManager.getOverlaySettingsIntent(context)
                        context.startActivity(intent)
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val intent = Intent(context, FloatingWindowManager::class.java).apply {
                        action = FloatingWindowManager.ACTION_START
                    }
                    context.startService(intent)
                    result.success(true)
                }
                "stopFloating" -> {
                    val intent = Intent(context, FloatingWindowManager::class.java).apply {
                        action = FloatingWindowManager.ACTION_STOP
                    }
                    context.startService(intent)
                    result.success(true)
                }
                "requestScreenshotPermission" -> {
                    // handled by activity
                    result.success(true)
                }
                "isFloatingShowing" -> {
                    result.success(FloatingWindowManager.getInstance()?.isFloatingWindowShowing() ?: false)
                }
                "saveScreenshotToGallery" -> {
                    val data = call.arguments as? ByteArray
                    if (data != null) {
                        FloatingWindowManager.getInstance()?.saveScreenshotToGallery(data)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "No image data provided", null)
                    }
                }
                "saveAiConfig" -> {
                    val apiUrl = call.argument<String>("apiUrl") ?: ""
                    val apiKey = call.argument<String>("apiKey") ?: ""
                    val model = call.argument<String>("model") ?: "glm-4v-flash"
                    val systemPrompt = call.argument<String>("systemPrompt") ?: ""
                    val directScreenshot = call.argument<Boolean>("directScreenshot") ?: false

                    val prefs = context.getSharedPreferences("ai_config", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString("api_url", apiUrl)
                        .putString("api_key", apiKey)
                        .putString("model", model)
                        .putString("system_prompt", systemPrompt)
                        .putBoolean("direct_screenshot", directScreenshot)
                        .apply()

                    FloatingWindowManager.getInstance()?.apply {
                        ai.apiUrl = apiUrl
                        ai.apiKey = apiKey
                        ai.model = model
                        ai.systemPrompt = systemPrompt
                        directScreenshotMode = directScreenshot
                    }
                    result.success(true)
                }
                "onAiAnswerChunk" -> {
                    val chunk = call.argument<String>("chunk") ?: ""
                    FloatingWindowManager.getInstance()?.appendAiAnswer(chunk)
                    result.success(true)
                }
                "onAiAnswerError" -> {
                    val error = call.argument<String>("error") ?: ""
                    FloatingWindowManager.getInstance()?.showAiError(error)
                    result.success(true)
                }
                "onAiAnswerStart" -> {
                    FloatingWindowManager.getInstance()?.showAiLoading()
                    result.success(true)
                }
                "onAiAnswerDone" -> {
                    FloatingWindowManager.getInstance()?.hideAiLoading()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun notifyPermissionGranted() {
        channel.invokeMethod("onScreenshotPermissionGranted", null)
    }

    fun notifyPermissionDenied() {
        channel.invokeMethod("onScreenshotPermissionDenied", null)
    }

    fun notifyRegionCaptured(data: ByteArray) {
        channel.invokeMethod("onRegionCaptured", data)
    }

    fun notifyAiQuestion(question: String, imagePath: String) {
        channel.invokeMethod("onAiQuestion", mapOf("question" to question, "imagePath" to imagePath))
    }
}
