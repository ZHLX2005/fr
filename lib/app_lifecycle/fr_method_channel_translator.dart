// fr:// 路由 MethodChannel 翻译器 —— 把原生 MethodChannel call(method + args)
// 翻译成项目内统一路由 URL,供 main.dart 的 _handleMethodCall 调用。
//
// 设计目的:
//   - 翻译表与 `bootstrap_routes.dart` 的注册表同目录可见
//   - 加新 widget → 改这一个文件 + bootstrap_routes + handler,不需进 main.dart
//   - 防腐蚀:把"method name → fr:// URL"的唯一映射关系收口到本文件
//
// 调用约定:
//   返回 null 表示该 method 不归本层管(常见情况:notImplemented);
//   调用方应保留旧行为:不 push、不抛错。
//
// 已支持的 method(与 WidgetChannel.kt 的 when 分支严格对称):
//   navigateToLab              → fr://lab
//   navigateToClock            → fr://lab/demo/clock
//   navigateToTimetable        → fr://timetable
//   navigateToNotionImage      → fr://notion/image-host?autocapture=<bool>
//   navigateToRecorder         → fr://lab/demo/recorder?autostart=<bool>
//   navigateToClockWidgetToggle→ fr://clock/widget-toggle
//   shareReceived              → fr://share/receive（载荷存 ShareReceiveStore.pending）

import 'package:flutter/services.dart';
import '../core/share_receive/share_receive_store.dart';

class FrMethodChannelTranslator {
  FrMethodChannelTranslator._();

  /// 同步翻译:输入 call,返回 fr:// URL 或 null。
  ///
  /// 不读 clock / context,纯字符串拼接 + 类型断言 —— 单元可测。
  static String? translate(MethodCall call) {
    return switch (call.method) {
      'navigateToLab' => 'fr://lab',
      'navigateToClock' => 'fr://lab/demo/clock',
      'navigateToTimetable' => 'fr://timetable',
      'navigateToNotionImage' =>
        'fr://notion/image-host?autocapture=${(call.arguments as bool?) ?? false}',
      'navigateToRecorder' =>
        'fr://lab/demo/recorder?autostart=${(call.arguments as bool?) ?? true}',
      'navigateToClockWidgetToggle' => 'fr://clock/widget-toggle',
      'shareReceived' => _translateShareReceived(call.arguments),
      _ => null,
    };
  }

  /// 分享接收：原生传 `{text: String?, files: List<String>}`，
  /// 载荷经 URL 不便传输（文本长/含特殊字符），存入
  /// [ShareReceiveStore.pending] 供 handler 页面消费，URL 仅作导航信号。
  static String? _translateShareReceived(Object? arguments) {
    final map = (arguments as Map?)?.cast<String, dynamic>() ?? const {};
    ShareReceiveStore.pending = ShareReceiveData(
      text: map['text'] as String?,
      fileUris: (map['files'] as List?)?.cast<String>() ?? const [],
    );
    return 'fr://share/receive';
  }
}