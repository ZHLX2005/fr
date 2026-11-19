import 'package:flutter/material.dart';

/// 日历页专用配色。
///
/// 仿滴答清单的浅青底 + 白色任务卡；暗色主题单独给一套低亮度版本，
/// 不直接复用全局 ColorScheme，避免其他页面的 sage 色调串进来。
@immutable
class CalendarPalette {
  const CalendarPalette({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentSoft,
    required this.divider,
    required this.completed,
    required this.shadow,
  });

  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color accentSoft;
  final Color divider;
  final Color completed;
  final Color shadow;

  factory CalendarPalette.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const CalendarPalette(
        background: Color(0xFF0D1A1D),
        surface: Color(0xFF17282C),
        textPrimary: Color(0xFFE8F4F5),
        textSecondary: Color(0xFF96ADB1),
        accent: Color(0xFF6FC4D1),
        accentSoft: Color(0xFF1E3B40),
        divider: Color(0xFF2A4449),
        completed: Color(0xFF6F8589),
        shadow: Color(0x33000000),
      );
    }
    return const CalendarPalette(
      background: Color(0xFFEDF8FA),
      surface: Color(0xFFFFFFFF),
      textPrimary: Color(0xFF1D2A2C),
      textSecondary: Color(0xFF7D9296),
      accent: Color(0xFF63B6C5),
      accentSoft: Color(0xFFD8EFF2),
      divider: Color(0xFFD8E8EB),
      completed: Color(0xFF9AACAF),
      shadow: Color(0x120B3A40),
    );
  }
}
