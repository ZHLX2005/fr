// 崩溃日志启动钩子 —— 在 main() 中 fire-and-forget 调用。
//
// 流程：
//   1) 通过 MethodChannel `io.github.xiaodouzi.fr/crash` 从原生侧读取
//      本次启动累积的 crash 日志（每条含 time + content）。
//   2) 把每条 crash 发射为 system event（eventType = 'app_crash_detected'）。
//   3) 调用原生 clearCrashLogs 防止下次启动再次重复报告。
//
// 失败被 catch（无原生通道 / 解析异常）—— 不阻塞启动。

import 'package:flutter/services.dart';
import '../core/ai_chat/system_messages/system_events_controller.dart';

/// 启动期一次性扫描原生 crash 日志并写入系统消息面板。
///
/// 调用方约定：fire-and-forget，失败不影响 main 同步链。
Future<void> runCrashLogIntakeOnStartup() async {
  const _channel = MethodChannel('io.github.xiaodouzi.fr/crash');
  List<dynamic>? raw;
  try {
    raw = await _channel.invokeMethod<List>('getCrashLogs');
  } catch (_) {
    // 原生通道未注册 / 引擎未就绪：静默退出
    return;
  }
  if (raw == null || raw.isEmpty) return;

  final controller = SystemEventsController();
  for (final item in raw) {
    try {
      final map = (item as Map).cast<String, dynamic>();
      final time = (map['time'] as String?) ?? '';
      final content = (map['content'] as String?) ?? '';
      // 把原始时间戳（通常形如 "2026-08-16_22-30-15"）保留
      // 内容超长时截前 200 字符到 detail，避免单条事件过长
      final detail = content.length > 200
          ? '${content.substring(0, 200)}…\n（已截断，原长度 ${content.length}）'
          : content;
      controller.append(
        eventType: 'app_crash_detected',
        title: 'App 崩溃（$time）',
        detail: detail,
      );
    } catch (_) {
      // 单条解析失败不影响其它 crash 落地
    }
  }

  // 通知原生侧清空日志，避免下次启动重复报告同一批崩溃
  try {
    await _channel.invokeMethod('clearCrashLogs');
  } catch (_) {}
}