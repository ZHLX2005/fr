# AI 视觉问答功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现区域截屏 + AI 视觉问答功能，原生层显示截图预览和问题输入框，Flutter 层配置 API 参数

**Architecture:** Native 层处理截图预览、AI 流式问答；Flutter 层管理配置；SharedPreferences 跨层共享配置；EventChannel 推送流式回答

**Tech Stack:** Kotlin (原生), Flutter/Dart, OkHttp SSE, MethodChannel, EventChannel, SharedPreferences

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `overlay_demo.dart` | 配置表单 UI（URL/Key/Model/Prompt），存储到 SharedPreferences |
| `FloatingWindowManager.kt` | 新增 ChatOverlayView（截图预览+问答 UI），OkHttp SSE 处理流式请求 |
| `MainActivity.kt` | 透传 MethodChannel 配置到 FloatingWindowManager |
| `overlay_service.dart` | 新增配置下发方法，EventChannel 接收流式回答 |

---

## 默认配置值

| 配置项 | 默认值 |
|--------|--------|
| API URL | `https://open.bigmodel.cn/api/paas/v4/chat/completions` |
| API Key | （用户填入） |
| Model | `glm-4v-flash` |
| System Prompt | `你是一个专业的AI助手，请根据图片回答用户问题。` |

---

## 任务分解

### 任务 1: Flutter 层配置表单与存储

**Files:**
- Modify: `lib/lab/demos/overlay_demo.dart`
- Modify: `lib/native/overlay/overlay_service.dart`

- [ ] **Step 1: 添加配置状态变量**

```dart
// API 配置
String _apiUrl = 'https://open.bigmodel.cn/api/paas/v4/chat/completions';
String _apiKey = '';
String _selectedModel = 'glm-4v-flash';
String _systemPrompt = '你是一个专业的AI助手，请根据图片回答用户问题。';

// 可用模型列表
final List<String> _availableModels = [
  'glm-4v-flash',
  'glm-5v-turbo',
  'glm-4.6v',
];
```

- [ ] **Step 2: 添加配置表单 UI**

在 `OverlayDemoPage` 的 `build` 方法中添加配置卡片：

```dart
Card(
  child: Padding(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI 配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(labelText: 'API URL', hintText: 'https://...'),
          controller: TextEditingController(text: _apiUrl),
          onChanged: (v) => _apiUrl = v,
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(labelText: 'API Key', hintText: 'your-api-key'),
          controller: TextEditingController(text: _apiKey),
          onChanged: (v) => _apiKey = v,
          obscureText: true,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedModel,
          decoration: const InputDecoration(labelText: '模型'),
          items: _availableModels.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
          onChanged: (v) => setState(() => _selectedModel = v!),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(labelText: '系统提示词'),
          controller: TextEditingController(text: _systemPrompt),
          onChanged: (v) => _systemPrompt = v,
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _saveConfig,
          child: const Text('保存配置'),
        ),
      ],
    ),
  ),
)
```

- [ ] **Step 3: 添加 _saveConfig 方法**

```dart
Future<void> _saveConfig() async {
  await _overlayService.saveAiConfig(
    apiUrl: _apiUrl,
    apiKey: _apiKey,
    model: _selectedModel,
    systemPrompt: _systemPrompt,
  );
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('配置已保存')),
    );
  }
}
```

- [ ] **Step 4: 在 overlay_service.dart 添加保存配置方法**

```dart
/// 保存 AI 配置到原生层
Future<void> saveAiConfig({
  required String apiUrl,
  required String apiKey,
  required String model,
  required String systemPrompt,
}) async {
  try {
    await _channel.invokeMethod('saveAiConfig', {
      'apiUrl': apiUrl,
      'apiKey': apiKey,
      'model': model,
      'systemPrompt': systemPrompt,
    });
  } on PlatformException catch (e) {
    debugPrint('保存配置失败: ${e.message}');
  }
}
```

- [ ] **Step 5: 提交任务 1**

```bash
git add lib/lab/demos/overlay_demo.dart lib/native/overlay/overlay_service.dart
git commit -m "feat(overlay): 添加 AI 配置表单 UI"
```

---

### 任务 2: 原生层配置接收与存储

**Files:**
- Modify: `MainActivity.kt`
- Modify: `FloatingWindowManager.kt`

- [ ] **Step 1: 在 MainActivity 添加 saveAiConfig handler**

在 FLOATING_CHANNEL 的 switch 中添加：

```kotlin
"saveAiConfig" -> {
    val apiUrl = call.argument<String>("apiUrl") ?: ""
    val apiKey = call.argument<String>("apiKey") ?: ""
    val model = call.argument<String>("model") ?: "glm-4v-flash"
    val systemPrompt = call.argument<String>("systemPrompt") ?: ""

    // 保存到 SharedPreferences
    getSharedPreferences("ai_config", Context.MODE_PRIVATE)
        .edit()
        .putString("api_url", apiUrl)
        .putString("api_key", apiKey)
        .putString("model", model)
        .putString("system_prompt", systemPrompt)
        .apply()

    result.success(true)
}
```

- [ ] **Step 2: 在 FloatingWindowManager 添加配置属性**

```kotlin
// AI 配置
var apiUrl: String = "https://open.bigmodel.cn/api/paas/v4/chat/completions"
var apiKey: String = ""
var model: String = "glm-4v-flash"
var systemPrompt: String = "你是一个专业的AI助手，请根据图片回答用户问题。"
```

- [ ] **Step 3: 在 onCreate 中加载配置**

```kotlin
override fun onCreate() {
    super.onCreate()
    instance = this
    createNotificationChannel()
    handler = Handler(thread.looper)
    loadAiConfig()  // 加载 AI 配置
}

private fun loadAiConfig() {
    try {
        val prefs = getSharedPreferences("ai_config", Context.MODE_PRIVATE)
        apiUrl = prefs.getString("api_url", apiUrl) ?: apiUrl
        apiKey = prefs.getString("api_key", apiKey) ?: apiKey
        model = prefs.getString("model", model) ?: model
        systemPrompt = prefs.getString("system_prompt", systemPrompt) ?: systemPrompt
    } catch (e: Exception) {
        e.printStackTrace()
    }
}
```

- [ ] **Step 4: 提交任务 2**

```bash
git add MainActivity.kt FloatingWindowManager.kt
git commit -m "feat(overlay): 原生层添加 AI 配置存储"
```

---

### 任务 3: 原生层 ChatOverlayView UI 实现

**Files:**
- Modify: `FloatingWindowManager.kt`

- [ ] **Step 1: 添加 ChatOverlayView 类**

在 `FloatingWindowManager.kt` 中添加：

```kotlin
/**
 * AI 问答视图 - 截图预览 + 问题输入 + AI 回答
 */
class ChatOverlayView(context: Context) : FrameLayout(context) {
    private var croppedBitmap: android.graphics.Bitmap? = null
    private var questionInput: EditText? = null
    private var answerText: TextView? = null
    private var sendButton: Button? = null
    private var closeButton: Button? = null
    private var loadingIndicator: ProgressBar? = null

    var onSendQuestion: ((String) -> Unit)? = null
    var onClose: (() -> Unit)? = null

    fun setBitmap(bitmap: android.graphics.Bitmap) {
        croppedBitmap = bitmap
        findViewById<ImageView>(R.id.preview_image)?.setImageBitmap(bitmap)
    }

    fun showLoading() {
        loadingIndicator?.visibility = VISIBLE
        answerText?.text = ""
    }

    fun appendAnswer(text: String) {
        loadingIndicator?.visibility = GONE
        val current = answerText?.text ?: ""
        answerText?.text = current + text
        // 自动滚动到底部
        (answerText?.parent as? ScrollView)?.post {
            (answerText?.parent as? ScrollView)?.fullScroll(View.FOCUS_DOWN)
        }
    }

    fun showError(message: String) {
        loadingIndicator?.visibility = GONE
        answerText?.text = "错误: $message"
    }

    fun clearAnswer() {
        answerText?.text = ""
    }
}
```

- [ ] **Step 2: 创建 chat_overlay.xml 布局文件**

创建 `res/layout/chat_overlay.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:background="#E6161616"
    android:padding="8dp">

    <!-- 顶部栏 -->
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:gravity="center_vertical">
        <TextView android:layout_width="0dp" android:layout_height="wrap_content"
            android:layout_weight="1" android:text="AI 视觉问答" android:textColor="#FFFFFF"
            android:textSize="16sp" android:textStyle="bold"/>
        <Button android:id="@+id/btn_close" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:text="关闭" android:textSize="12sp"/>
    </LinearLayout>

    <!-- 截图预览 -->
    <ImageView android:id="@+id/preview_image" android:layout_width="match_parent"
        android:layout_height="0dp" android:layout_weight="1" android:scaleType="fitCenter"
        android:background="#333333" android:layout_marginTop="8dp"/>

    <!-- 问题输入 -->
    <LinearLayout android:layout_width="match_parent" android:layout_height="wrap_content"
        android:orientation="horizontal" android:layout_marginTop="8dp">
        <EditText android:id="@+id/question_input" android:layout_width="0dp"
            android:layout_height="wrap_content" android:layout_weight="1"
            android:hint="输入问题..." android:textColorHint="#888888"
            android:textColor="#FFFFFF" android:background="@android:drawable/edit_text"
            android:padding="8dp"/>
        <Button android:id="@+id/btn_send" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:text="发送" android:layout_marginStart="8dp"/>
    </LinearLayout>

    <!-- AI 回答 -->
    <FrameLayout android:layout_width="match_parent" android:layout_height="120dp"
        android:layout_marginTop="8dp">
        <ScrollView android:layout_width="match_parent" android:layout_height="match_parent">
            <TextView android:id="@+id/answer_text" android:layout_width="match_parent"
                android:layout_height="wrap_content" android:textColor="#FFFFFF"
                android:textSize="14sp"/>
        </ScrollView>
        <ProgressBar android:id="@+id/loading" android:layout_width="wrap_content"
            android:layout_height="wrap_content" android:layout_gravity="center"
            android:visibility="gone"/>
    </FrameLayout>
</LinearLayout>
```

- [ ] **Step 3: 修改 showPreviewOverlay 替换为 ChatOverlayView**

将 `showPreviewOverlay` 方法替换为使用布局：

```kotlin
private fun showChatOverlay(croppedBitmap: android.graphics.Bitmap) {
    val chatView = ChatOverlayView(this).apply {
        setBitmap(croppedBitmap)
        onSendQuestion = { question ->
            // 发送问题到 Flutter 处理
            sendQuestionToFlutter(question, croppedBitmap)
        }
        onClose = {
            hideChatOverlay()
            croppedBitmap.recycle()
            showFloatingWindow()
        }
    }

    val params = WindowManager.LayoutParams(
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.MATCH_PARENT,
        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
        PixelFormat.TRANSLUCENT
    )

    try {
        windowManager?.addView(chatView, params)
        chatOverlay = chatView
    } catch (e: Exception) {
        e.printStackTrace()
    }
}

private var chatOverlay: ChatOverlayView? = null

private fun hideChatOverlay() {
    chatOverlay?.let {
        try {
            windowManager?.removeView(it)
        } catch (e: Exception) {
            // 忽略
        }
        chatOverlay = null
    }
}
```

- [ ] **Step 4: 添加 sendQuestionToFlutter 方法**

```kotlin
private fun sendQuestionToFlutter(question: String, bitmap: android.graphics.Bitmap) {
    // 将 bitmap 转为字节数组，通过 MethodChannel 发送给 Flutter
    val stream = java.io.ByteArrayOutputStream()
    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
    val byteArray = stream.toByteArray()

    try {
        val intent = Intent("com.example.flutter_application_1.AI_QUESTION").apply {
            putExtra("question", question)
            putExtra("image_data", byteArray)
            setPackage(packageName)
        }
        sendBroadcast(intent)
    } catch (e: Exception) {
        e.printStackTrace()
        chatOverlay?.showError("发送失败: ${e.message}")
    }
}
```

- [ ] **Step 5: 提交任务 3**

```bash
git add FloatingWindowManager.kt res/layout/chat_overlay.xml
git commit -m "feat(overlay): 添加 ChatOverlayView UI"
```

---

### 任务 4: Flutter 层 AI API 调用与流式处理

**Files:**
- Modify: `MainActivity.kt`
- Modify: `overlay_service.dart`
- Modify: `overlay_demo.dart`

- [ ] **Step 1: 在 MainActivity 注册 AI_QUESTION 广播接收器**

```kotlin
private var aiQuestionReceiver: BroadcastReceiver? = null

private fun registerAiQuestionReceiver() {
    if (aiQuestionReceiver != null) return
    aiQuestionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.flutter_application_1.AI_QUESTION") {
                val question = intent.getStringExtra("question") ?: return
                val imageData = intent.getByteArrayExtra("image_data") ?: return
                // 通过 MethodChannel 通知 Flutter
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, FLOATING_CHANNEL)
                        .invokeMethod("onAiQuestion", mapOf(
                            "question" to question,
                            "imageData" to imageData
                        ))
                }
            }
        }
    }
    val filter = IntentFilter("com.example.flutter_application_1.AI_QUESTION")
    registerReceiver(aiQuestionReceiver, filter)
}

override fun onDestroy() {
    super.onDestroy()
    aiQuestionReceiver?.let { unregisterReceiver(it) }
}
```

- [ ] **Step 2: 在 onResume 中调用注册**

在 `onResume` 方法中添加 `registerAiQuestionReceiver()` 调用。

- [ ] **Step 3: 在 overlay_service.dart 添加 EventChannel 接收流式回答**

```dart
static const _eventChannel = EventChannel('com.example.flutter_application_1/floating_events');

Stream<String>? _aiAnswerStream;
Stream<String> get aiAnswerStream {
  _aiAnswerStream ??= _eventChannel
      .receiveBroadcastStream()
      .map((event) => event as String);
  return _aiAnswerStream!;
}
```

- [ ] **Step 4: 在 overlay_service.dart 添加 invokeAiQuestion 方法**

```dart
Future<void> invokeAiQuestion(String question, Uint8List imageData) async {
  try {
    await _channel.invokeMethod('callAiApi', {
      'question': question,
      'imageData': imageData,
    });
  } on PlatformException catch (e) {
    debugPrint('调用 AI 失败: ${e.message}');
  }
}
```

- [ ] **Step 5: 在 overlay_service.dart 添加 sendAiAnswerChunk 方法**

```dart
void sendAiAnswerChunk(String chunk) {
  // 通过 EventChannel 发送 chunk 给原生层
  // 注意：EventChannel 只能从 Flutter 发往原生，这里我们用 MethodChannel 回传
}
```

实际上 EventChannel 是原生→Flutter 的单向通道。我们需要用其他方式。

**替代方案：用 MethodChannel 轮询或直接由原生处理 SSE**

考虑到复杂性，更好的方案是：
- 原生层直接用 OkHttp SSE 调用 AI API
- Flutter 只负责配置下发

让我重新设计这个任务...

- [ ] **Step 5 (修订): 修改为原生层直接处理 SSE**

**原生层直接调用 AI API：**

```kotlin
private fun callAiApi(question: String, bitmap: android.graphics.Bitmap) {
    if (apiKey.isEmpty()) {
        chatOverlay?.showError("请先配置 API Key")
        return
    }

    chatOverlay?.showLoading()

    Thread {
        try {
            val url = URL(apiUrl)
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Authorization", "Bearer $apiKey")
            conn.doOutput = true
            conn.doInput = true
            conn.connectTimeout = 30000
            conn.readTimeout = 120000

            // 构建请求体
            val base64Image = android.util.Base64.encodeToString(
                imageToByteArray(bitmap),
                android.util.Base64.NO_WRAP
            )

            val jsonBody = """
            {
                "model": "$model",
                "messages": [
                    {"role": "system", "content": "$systemPrompt"},
                    {"role": "user", "content": [
                        {"type": "image_url", "image_url": {"url": "data:image/png;base64,$base64Image"}},
                        {"type": "text", "text": "$question"}
                    ]}
                ],
                "stream": true
            }
            """.trimIndent()

            conn.outputStream.write(jsonBody.toByteArray())
            conn.outputStream.flush()

            val responseCode = conn.responseCode
            if (responseCode != 200) {
                handler.post {
                    chatOverlay?.showError("API 错误: $responseCode")
                }
                return@Thread
            }

            // 处理 SSE 流
            val reader = BufferedReader(InputStreamReader(conn.inputStream))
            val buffer = StringBuffer()
            var line: String?

            while ((reader.readLine().also { line = it }) != null) {
                if (line!!.startsWith("data: ")) {
                    val data = line!!.substring(6)
                    if (data == "[DONE]") break

                    // 解析 SSE data
                    val chunk = parseSseData(data)
                    if (chunk.isNotEmpty()) {
                        handler.post {
                            chatOverlay?.appendAnswer(chunk)
                        }
                    }
                }
            }

            reader.close()
            conn.disconnect()

        } catch (e: Exception) {
            e.printStackTrace()
            handler.post {
                chatOverlay?.showError("请求失败: ${e.message}")
            }
        }
    }.start()
}

private fun imageToByteArray(bitmap: android.graphics.Bitmap): ByteArray {
    val stream = java.io.ByteArrayOutputStream()
    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
    return stream.toByteArray()
}

private fun parseSseData(json: String): String {
    // 解析 BigModel SSE 响应格式
    // 格式: {"choices":[{"delta":{"content":"xxx"}}]}
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
```

- [ ] **Step 6: 提交任务 4**

```bash
git add MainActivity.kt overlay_service.dart
git commit -m "feat(overlay): Flutter 层 AI 调用和流式处理"
```

---

### 任务 5: 修改 cropAndSendBitmap 后的流程

**Files:**
- Modify: `FloatingWindowManager.kt`

- [ ] **Step 1: 修改 cropAndSendBitmap 末尾调用 showChatOverlay**

将 `showPreviewOverlay(croppedBitmap)` 替换为 `showChatOverlay(croppedBitmap)`：

```kotlin
// 显示原生问答视图
showChatOverlay(croppedBitmap)
```

- [ ] **Step 2: 移除不再使用的 showPreviewOverlay 和相关代码**

删除 `showPreviewOverlay`、`hidePreviewOverlay`、`previewOverlay`、`previewBackground` 相关代码。

- [ ] **Step 3: 提交任务 5**

```bash
git add FloatingWindowManager.kt
git commit -m "feat(overlay): 对接 AI 问答流程"
```

---

### 任务 6: 测试和验证

- [ ] **Step 1: 编译并运行**

```bash
flutter clean && flutter run
```

- [ ] **Step 2: 测试流程**

1. 打开悬浮截屏 Demo
2. 配置 API Key 和其他参数，点击保存
3. 点击"显示悬浮窗"
4. 点击悬浮按钮，拖动选择区域
5. 确认屏幕上显示截图预览 + 问题输入框
6. 输入问题，点击发送
7. 确认 AI 回答流式显示

- [ ] **Step 3: 提交最终更改**

```bash
git add -A
git commit -m "feat(overlay): 完成 AI 视觉问答功能"
```

---

## 验证清单

| 功能 | 预期 |
|------|------|
| 配置表单 | URL/Key/Model/Prompt 均可配置并保存 |
| 配置持久化 | 重启后配置保持 |
| 截图预览 | 选中区域后显示截图 |
| 问题输入 | 可以输入问题并发送 |
| 流式回答 | AI 回答实时流式显示 |
| 关闭返回 | 点击关闭后恢复悬浮窗图标 |
