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
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.accentSoft,
    required this.divider,
    required this.completed,
    required this.shadow,
    required this.danger,
    required this.overlay,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final Color accent;
  final Color accentSoft;
  final Color divider;
  final Color completed;
  final Color shadow;
  final Color danger;
  final Color overlay;

  factory CalendarPalette.of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const CalendarPalette(
        background: Color(0xFF0B181B),
        surface: Color(0xFF16272B),
        surfaceAlt: Color(0xFF1D3237),
        textPrimary: Color(0xFFEAF7F8),
        textSecondary: Color(0xFF91A9AD),
        accent: Color(0xFF76C9D6),
        accentSoft: Color(0xFF1C3B40),
        divider: Color(0xFF274247),
        completed: Color(0xFF6A8286),
        shadow: Color(0x55000000),
        danger: Color(0xFFE48787),
        overlay: Color(0xFF20363B),
      );
    }
    return const CalendarPalette(
      background: Color(0xFFEAF8FA),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF4FBFC),
      textPrimary: Color(0xFF1D2A2C),
      textSecondary: Color(0xFF8DA1A4),
      accent: Color(0xFF70BFCB),
      accentSoft: Color(0xFFD5EFF3),
      divider: Color(0xFFDCEAEC),
      completed: Color(0xFFA1B2B5),
      shadow: Color(0x140B3A40),
      danger: Color(0xFFD86C6C),
      overlay: Color(0xFFF9FDFE),
    );
  }
}

/// 任务图标用的柔和色盘；没有显式 color 时按任务 id 取一个稳定色。
const List<Color> kCalendarTaskColors = [
  Color(0xFF8A83D4),
  Color(0xFF63C39E),
  Color(0xFFE1A45A),
  Color(0xFF6FA6D7),
  Color(0xFFD77E9B),
  Color(0xFFB18AD8),
];

Color calendarTaskColor(int? value, int id) {
  if (value != null) return Color(value);
  return kCalendarTaskColors[id.abs() % kCalendarTaskColors.length];
}
