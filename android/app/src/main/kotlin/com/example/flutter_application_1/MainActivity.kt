package com.example.flutter_application_1

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.flutter_application_1/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 设置 MethodChannel 处理来自 Widget 的跳转请求
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "navigateToLab") {
                // 跳转到 Lab 页面
                navigateToLab()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // 处理深层链接
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        // 处理启动时的 Intent
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        intent?.data?.let { uri ->
            // 检查是否是 fr://lab
            if (uri.toString() == "fr://lab" || uri.path == "/lab") {
                // 通过 MethodChannel 通知 Flutter 跳转
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, CHANNEL).invokeMethod("navigateToLab", null)
                }
            }
        }
    }

    private fun navigateToLab() {
        // 通知 Flutter 导航到 Lab 页面
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, CHANNEL).invokeMethod("navigateToLab", null)
        }
    }
}
