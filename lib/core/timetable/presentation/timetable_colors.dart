import 'package:flutter/material.dart';
import '../../../widgets/theme/zen_theme.dart';

/// 课表配色 —— 课程身份色 + Zen 主题背景色。
///
/// - 课程身份色（[courseColors]/[getCourseColor]）：莫兰迪 8 色，保留为课程的视觉
///   标识，不随主题切换（与桌面小组件 TimetableWidgetColors 同源）。
/// - 背景/边框/文字色：委托 [ZenColors]，与全局 zen 暖米系对齐（clock/recorder/
/// timetable 设置页同源）。
class TimetableColors {
  TimetableColors._();

  /// 莫兰迪色系 - 用于课程单元格背景（保留为课程身份色）
  static const List<Color> courseColors = [
    Color(0xFF8B9DC3), // 灰蓝
    Color(0xFF9E8FA8), // 灰紫
    Color(0xFFB58AA5), // 灰粉
    Color(0xFFC49A8B), // 灰橘
    Color(0xFFA8C4A2), // 灰绿
    Color(0xFF7FAAAA), // 灰青
    Color(0xFFA5B5C4), // 雾蓝
    Color(0xFFC4B5A0), // 灰棕
  ];

  /// 获取课程颜色（课程身份色，不随主题）
  static Color getCourseColor(int seed) {
    return courseColors[seed % courseColors.length];
  }

  // ──────── 背景/边框/文字色：委托 ZenColors（暖米系） ────────

  /// 边框强调色 - 中性灰（→ ZenColors.secondary 暖灰）
  static Color get accent => ZenColors.secondary;

  /// 浅灰强调（→ ZenColors.secondary）
  static Color get accentLight => ZenColors.secondary;

  /// 鼠尾草绿 - "今天"列头高亮 / 主操作强调
  static Color get sage => ZenColors.sage;

  /// 选中状态背景（→ ZenColors.surface 卡片底）
  static Color get selectedBg => ZenColors.surface;

  /// 边框色（→ ZenColors.hair 发丝线）
  static Color get border => ZenColors.hair;

  /// 浅边框（→ ZenColors.surface）
  static Color get borderLight => ZenColors.surface;

  /// 文字色
  static Color get textPrimary => ZenColors.ink;
  static Color get textSecondary => ZenColors.secondary;
  static Color get textTertiary => ZenColors.hair; // 最浅（发丝线）

  /// 背景色
  static Color get surface => ZenColors.bg;
  static Color get surfaceVariant => ZenColors.surface;
}
