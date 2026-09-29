import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 全局错误可视化 —— 让 release 包里的异常**不再是白屏**。
///
/// ## 为什么需要它（踩过的坑，别删）
///
/// Flutter 默认的 `ErrorWidget.Builder` 在 **release 构建**下会退化成一块
/// **无字浅灰矩形**：
/// - `framework.dart` 的默认 builder 把 message 放在 `assert(() {...}())` 里，
///   release 下 assert 被剥离 → `message = ''`
/// - `rendering/error.dart` 里 `if (_paragraph != null)` 判断后才画字，
///   message 为空 → 不画任何文字，只画 `Color(0xF0C0C0C0)`
///
/// 结果：任何一处在 build 期抛异常，用户看到的就是「整页完全空白」——
/// 而同一处异常在 debug/test 下是红底黄字的可读错误屏。这正是线上
/// 「测试全过、APK 白屏」的机制来源。
///
/// 装上本兜底后：release 下也渲染**带异常文本的红色卡片**，用户能截图、
/// 能看出是哪个页面出的问题；`debugPrint` 同时写日志，`adb logcat` 可抓。
class GlobalsErrorGuard {
  GlobalsErrorGuard._();

  static bool _installed = false;

  /// 在 `runApp` **之前**调用一次（幂等）。
  static void install() {
    if (_installed) return;
    _installed = true;

    // 1) build 期异常 → 可见错误卡片（这是把「白屏」变「可读」的关键一环）
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return _ErrorCard(details: details);
    };

    // 2) 框架层未捕获异常：照常打印（release 也能进 logcat），不吞掉
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      previous?.call(details);
      debugPrint('[error-guard] FlutterError: ${details.exceptionAsString()}');
      debugPrint('${details.stack}');
    };

    // 3) 非框架层（异步 / 平台回调）未捕获异常：打日志，避免静默失败
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      debugPrint('[error-guard] Uncaught: $error');
      debugPrint('$stack');
      return true; // 已处理，不再向上抛（避免 release 闪退）
    };
  }
}

/// build 期异常的错误卡片：标题 + 异常文本（可选中复制）+ 页面栈提示。
class _ErrorCard extends StatelessWidget {
  final FlutterErrorDetails details;

  const _ErrorCard({required this.details});

  @override
  Widget build(BuildContext context) {
    final message = details.exceptionAsString();
    // 保证在任何 context 下都能画出东西（不依赖 Theme，因为出错的可能就是 Theme）
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFFB00020),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '页面渲染出错',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              if (details.library != null) ...[
                const SizedBox(height: 6),
                SelectableText(
                  '来源: ${details.library}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
