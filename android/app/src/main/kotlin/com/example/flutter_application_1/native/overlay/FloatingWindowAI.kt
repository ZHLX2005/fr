package com.example.flutter_application_1.native.overlay

import android.os.Handler
import android.util.Base64
import java.io.BufferedReader
import java.io.File
import java.io.FileInputStream
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * AI 调用模块
 */
class FloatingWindowAI(
    private val handler: Handler,
    private val screenshot: FloatingWindowScreenshot
) {
    var apiUrl: String = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
    var apiKey: String = ""
    var model: String = "glm-4v-flash"
    var systemPrompt: String = "你是一个专业的AI助手，请根据图片回答用户问题。"

    private var _chatOverlay: ChatOverlayView? = null
    val chatOverlay: ChatOverlayView? get() = _chatOverlay

    fun setChatOverlay(chatOverlay: ChatOverlayView?) {
        this._chatOverlay = chatOverlay
    }

    fun callAiApi(question: String, imagePath: String) {
        handler.post { _chatOverlay?.showLoading() }

        Thread {
            try {
                val file = File(imagePath)
                val imageBytes = FileInputStream(file).use { it.readBytes() }
                val imageBase64 = Base64.encodeToString(imageBytes, Base64.NO_WRAP)

                val messages = """
                    [
                        {"role": "system", "content": "$systemPrompt"},
                        {"role": "user", "content": [
                            {"type": "image_url", "image_url": {"url": "data:image/png;base64,$imageBase64"}},
                            {"type": "text", "text": "$question"}
                        ]}
                    ]
                """.trimIndent()

                val jsonBody = """
                    {
                        "model": "$model",
                        "messages": $messages,
                        "stream": true,
                        "thinking": {"type": "disabled"}
                    }
                """.trimIndent()

                val url = URL(apiUrl)
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setRequestProperty("Authorization", "Bearer $apiKey")
                connection.connectTimeout = 30000
                connection.readTimeout = 30000

                OutputStreamWriter(connection.outputStream).use { writer ->
                    writer.write(jsonBody)
                    writer.flush()
                }

                val responseCode = connection.responseCode
                if (responseCode != 200) {
                    handler.post {
                        _chatOverlay?.showError("API 错误: $responseCode")
                        _chatOverlay?.hideLoading()
                    }
                    connection.disconnect()
                    return@Thread
                }

                BufferedReader(InputStreamReader(connection.inputStream)).use { reader ->
                    var line: String?
                    while (reader.readLine().also { line = it } != null) {
                        line = line?.trim()
                        if (line.isNullOrEmpty()) continue

                        if (line!!.startsWith("data: ")) {
                            val data = line!!.substring(6)
                            if (data == "[DONE]") break

                            val content = parseSseData(data)
                            if (content.isNotEmpty()) {
                                handler.post {
                                    _chatOverlay?.appendAnswer(content)
                                }
                            }
                        }
                    }
                }

                connection.disconnect()
                handler.post { _chatOverlay?.hideLoading() }

                try { file.delete() } catch (e: Exception) { /* 忽略 */ }

            } catch (e: Exception) {
                handler.post {
                    _chatOverlay?.showError("请求失败: ${e.message}")
                    _chatOverlay?.hideLoading()
                }
            }
        }.start()
    }

    private fun parseSseData(json: String): String {
        return try {
            val obj = org.json.JSONObject(json)
            val choices = obj.optJSONArray("choices")
            if (choices != null && choices.length() > 0) {
                val delta = choices.getJSONObject(0).optJSONObject("delta")
                delta?.optString("content") ?: ""
            } else ""
        } catch (e: Exception) {
            ""
        }
    }
}
