// 下拉面板配色：由 ColorScheme 推导，亮暗主题自适应。

import 'package:flutter/material.dart';

import '../../../../core/color/color_utils.dart';

class LabPanelColors {
  final Color gradientTop;
  final Color gradientMiddle;
  final Color gradientBottom;
  final Color accent;
  final Color accentSoft;
  final Color accentDeep;
  final Color text;
  final Color mutedText;
  final Color glassFill;
  final Color glassBorder;
  final bool isDark;

  const LabPanelColors({
    required this.gradientTop,
    required this.gradientMiddle,
    required this.gradientBottom,
    required this.accent,
    required this.accentSoft,
    required this.accentDeep,
    required this.text,
    required this.mutedText,
    required this.glassFill,
    required this.glassBorder,
    required this.isDark,
  });

  factory LabPanelColors.resolve(
    ColorScheme cs, {
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    return LabPanelColors(
      // 渐变背景：surface → surfaceContainerHighest，使用主题设计好的色阶
      gradientTop: cs.surface,
      gradientMiddle: ColorUtils.mix(
        cs.surface,
        cs.surfaceContainerHighest,
        0.5,
      ),
      gradientBottom: cs.surfaceContainerHighest,
      // 强调色：直接使用 ColorScheme 设计好的主色关系
      accent: cs.primary,
      accentSoft: cs.primaryContainer,
      accentDeep: cs.onPrimaryContainer,
      // 文字色
      text: cs.onSurface,
      mutedText: cs.onSurfaceVariant,
      // 毛玻璃容器：用 surface 半透明，自然适配亮暗
      glassFill: cs.surface.withValues(alpha: isDark ? 0.18 : 0.60),
      glassBorder: cs.surface.withValues(alpha: isDark ? 0.12 : 0.50),
      isDark: isDark,
    );
  }
}
