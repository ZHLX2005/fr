// Layer 1 — Lemon 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class LemonColors {
  LemonColors._();

  /// 柠檬鼠尾草主题（light）—— 黄油主色 + 暖石中性 + 低彩鼠尾草稀强调。
  ///
  /// 2026-10-12 重配（theme-color-cards 提案通过）：
  /// 去掉闲鱼高彩黄 / 蓝灰字 / 草绿 / 尿黄托盘，改为暖石家族结构。
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFE4C44A),
    onPrimary: Color(0xFF2C2A22),
    primaryContainer: Color(0xFFF3EBC8),
    onPrimaryContainer: Color(0xFF3A3520),
    secondary: Color(0xFF8A8578),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEAE6DA),
    onSecondaryContainer: Color(0xFF2C2A22),
    tertiary: Color(0xFF6B8F71),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD8E6DA),
    onTertiaryContainer: Color(0xFF1E3324),
    surface: Color(0xFFFFFEFA),
    onSurface: Color(0xFF2C2A24),
    onSurfaceVariant: Color(0xFF7A7568),
    surfaceContainerHighest: Color(0xFFF3F0E6),
    error: Color(0xFFC45C4A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF0D8D2),
    onErrorContainer: Color(0xFF4A1F18),
    outline: Color(0xFFE5E0D4),
    outlineVariant: Color(0xFFEFEBE0),
    surfaceTint: Color(0xFFE4C44A),
  );

  /// lemon 主题 AppColorsExtension
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF6B8F71),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD8E6DA),
    onSuccessContainer: Color(0xFF1E3324),
    warning: Color(0xFFE4C44A),
    onWarning: Color(0xFF2C2A22),
    warningContainer: Color(0xFFF3EBC8),
    onWarningContainer: Color(0xFF3A3520),
    info: Color(0xFF6B8F71),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFD8E6DA),
    onInfoContainer: Color(0xFF1E3324),
    category: [
      Color(0xFFF3EBC8),
      Color(0xFFE4C44A),
      Color(0xFF6B8F71),
      Color(0xFF2C2A24),
      Color(0xFF8A8578),
      Color(0xFFF3F0E6),
      Color(0xFFFFFEFA),
      Color(0xFF3A3520),
    ],
  );
}
