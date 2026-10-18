// Layer 1 — Purple 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class PurpleColors {
  PurpleColors._();

  /// 暮紫主题（dark）— 冷炭紫环境 + 清晰暮紫主色 + 稀用鎏金。
  ///
  /// 2026-10-12 重配（对齐 theme-color-cards 提案）：
  /// 去掉棕黑底 / 暖褐灰 secondary，避免紫+金+棕三族混浊。
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFB9A6D6),
    onPrimary: Color(0xFF1A1524),
    primaryContainer: Color(0xFF3A2F54),
    onPrimaryContainer: Color(0xFFEAE3F7),
    secondary: Color(0xFF9B97AB),
    onSecondary: Color(0xFF1A1822),
    secondaryContainer: Color(0xFF2C2A38),
    onSecondaryContainer: Color(0xFFE4E0EF),
    tertiary: Color(0xFFD2BA7A),
    onTertiary: Color(0xFF1A1520),
    tertiaryContainer: Color(0xFF3F3520),
    onTertiaryContainer: Color(0xFFF0E2B8),
    surface: Color(0xFF1A1822),
    onSurface: Color(0xFFE8E6F0),
    onSurfaceVariant: Color(0xFF9B97AB),
    surfaceContainerHighest: Color(0xFF13111A),
    error: Color(0xFFE090B0),
    onError: Color(0xFF1A1520),
    errorContainer: Color(0xFF6E3A52),
    onErrorContainer: Color(0xFFF5D4E4),
    outline: Color(0xFF3A3648),
    outlineVariant: Color(0xFF2A2736),
    surfaceTint: Color(0xFFB9A6D6),
  );

  /// purple 主题 AppColorsExtension
  /// info 用鎏金（稀强调）；category 跨冷紫 / 金，不再掺棕灰
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF8FBEA4),
    onSuccess: Color(0xFF1A1520),
    successContainer: Color(0xFF243A2E),
    onSuccessContainer: Color(0xFFB8D6C4),
    warning: Color(0xFFD2BA7A),
    onWarning: Color(0xFF1A1520),
    warningContainer: Color(0xFF3F3520),
    onWarningContainer: Color(0xFFF0E2B8),
    info: Color(0xFFD2BA7A),
    onInfo: Color(0xFF1A1520),
    infoContainer: Color(0xFF3F3520),
    onInfoContainer: Color(0xFFF0E2B8),
    category: [
      Color(0xFFEAE3F7),
      Color(0xFFB9A6D6),
      Color(0xFF9B97AB),
      Color(0xFF1A1822),
      Color(0xFFD2BA7A),
      Color(0xFF3A2F54),
      Color(0xFFE8E6F0),
      Color(0xFF13111A),
    ],
  );
}
