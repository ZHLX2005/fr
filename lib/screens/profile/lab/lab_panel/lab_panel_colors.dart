// 下拉面板配色：由 ColorScheme 推导，亮暗主题自适应。

import 'package:flutter/material.dart';

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
      // 三段取同一个值 = 平色。面板底与页面背景（scaffoldBackgroundColor
      // 在 M3 下即 colorScheme.surface）完全一致，展开时不会在底部留一层
      // 「更沉的表面」。保留渐变结构而不换 widget：改动面越小越好定位。
      gradientTop: cs.surface,
      gradientMiddle: cs.surface,
      gradientBottom: cs.surface,
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
