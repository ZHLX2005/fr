import 'package:flutter/material.dart';

/// 日历页专用配色适配层。
///
/// 所有颜色派生自当前主题的 [ColorScheme]（成对角色：primary/primaryContainer、
/// surface 系容器 + onSurface/onSurfaceVariant 前景），7 套主题（purple/zen/ink/
/// rose/lemon/cobalt/dark）自动生效；不再维护明暗两套硬编码 hex。
@immutable
class CalendarPalette {
  const CalendarPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
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

  /// accent 的成对前景（scheme.onPrimary）：accent 底上的图标/文字必须用它。
  final Color onAccent;
  final Color accentSoft;
  final Color divider;
  final Color completed;
  final Color shadow;
  final Color danger;
  final Color overlay;

  factory CalendarPalette.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CalendarPalette(
      background: scheme.surface,
      surface: scheme.surfaceContainerLow,
      surfaceAlt: scheme.surfaceContainer,
      textPrimary: scheme.onSurface,
      textSecondary: scheme.onSurfaceVariant,
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      accentSoft: scheme.primaryContainer,
      divider: scheme.outlineVariant,
      completed: scheme.onSurfaceVariant,
      shadow: scheme.scrim.withValues(alpha: 0.20),
      danger: scheme.error,
      overlay: scheme.surfaceContainerLow,
    );
  }
}

/// 任务色盘：**数据语义色**（任务归属标记，用户可选的稳定身份色），
/// 按主题通道审计 §8 规则 2 在 docs/architecture/theme-channel-audit.md 登记
/// 豁免；不随主题变化以保持任务数据的可识别性。
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
