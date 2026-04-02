import 'package:flutter/material.dart';

/// 课表专属低饱和度配色方案
/// 与系统主题色隔离，提供柔和的视觉体验
class TimetableColors {
  TimetableColors._();

  /// 莫兰迪色系 - 用于课程单元格背景
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

  /// 获取课程颜色
  static Color getCourseColor(int seed) {
    return courseColors[seed % courseColors.length];
  }

  /// 边框强调色 - 低饱和度中性色
  static const Color accent = Color(0xFF6B7280); // 中性灰
  static const Color accentLight = Color(0xFF9CA3AF); // 浅灰

  /// 选中状态背景 - 极淡灰色
  static const Color selectedBg = Color(0xFFF3F4F6);

  /// 边框色
  static const Color border = Color(0xFFE5E7EB);
  static const Color borderLight = Color(0xFFF3F4F6);

  /// 文字色
  static const Color textPrimary = Color(0xFF374151);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);

  /// 背景色
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF9FAFB);
}
