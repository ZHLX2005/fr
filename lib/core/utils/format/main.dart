// Lab 通用时间格式化工具（2026-10 从 lib/core/ui/global/zen/main.dart 迁出）。
//
// 原位置：zen_theme.dart 把 3 个 format 函数与主题样式混在一起；
// 实际上它们只被 clock/recorder demo 使用，与主题/UI 无关。
// 归位：lib/lab/utils/time_format.dart（lab demos 通用工具）。

/// 把秒数格式化为紧凑时长字符串（如 "1h 2m 3s" / "2m 30s" / "45s"）。
String formatDuration(int seconds) {
  if (seconds <= 0) return '0s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

/// 把秒数格式化为 hh:mm:ss 或 mm:ss 时长字符串（可处理负数）。
String formatTime(int seconds) {
  final isNegative = seconds < 0;
  final absSeconds = seconds.abs();
  final h = absSeconds ~/ 3600;
  final m = (absSeconds % 3600) ~/ 60;
  final s = absSeconds % 60;
  final sign = isNegative ? '-' : '';
  if (h > 0) {
    return '$sign${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
  return '$sign${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 把 DateTime 格式化为 "yyyy-MM-dd HH:mm" 记录时间字符串。
String formatRecordDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
