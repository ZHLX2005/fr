// 下拉面板配色：由 ColorScheme 推导，亮暗主题自适应。

import 'package:flutter/material.dart';

class LabPanelColors {
  /// 面板底色 —— 与页面背景（`colorScheme.surface`）**完全同一个值**。
  ///
  /// 这里原先是一段 surface → surfaceContainerHighest 的纵向渐变，展开后
  /// 下半截比页面背景更沉，整块读起来像贴在页底的深色色块。浮卡本身不改，
  /// 只把面板底色拉平到背景：面板展开时不再有「另一层表面」的边界。
  final Color background;
  final Color accent;
  final Color accentSoft;
  final Color accentDeep;
  final Color text;
  final Color mutedText;
  final Color glassFill;
  final Color glassBorder;
  final bool isDark;

  const LabPanelColors({
    required this.background,
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
      // 与页面背景同值：浮卡浮在「同一张纸」上，而不是浮在另一块底色上。
      background: cs.surface,
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
