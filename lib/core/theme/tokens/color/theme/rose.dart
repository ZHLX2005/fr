// Layer 1 — Rose 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class RoseColors {
  RoseColors._();

  /// 粉雾海盐主题（light）—— Velvet Bloom 粉主色 + 海盐薄荷互补撞色 + 纯白背景。
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFF49399),
    onPrimary: Color(0xFF3A2A2D),
    primaryContainer: Color(0xFFFECBCB),
    onPrimaryContainer: Color(0xFF4A1F24),
    secondary: Color(0xFFA69297),
    onSecondary: Color(0xFF3A2A2D),
    secondaryContainer: Color(0xFFF1B3B8),
    onSecondaryContainer: Color(0xFF4A1F24),
    tertiary: Color(0xFF7CA9A4),
    onTertiary: Color(0xFF1E3A36),
    tertiaryContainer: Color(0xFFD8E9E5),
    onTertiaryContainer: Color(0xFF143B36),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF3A2A2D),
    onSurfaceVariant: Color(0xFF8A6F74),
    surfaceContainerHighest: Color(0xFFEDD8DC),
    error: Color(0xFFB04650),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFE8CCD0),
    onErrorContainer: Color(0xFF3F1518),
    outline: Color(0xFFEADEE1),
    outlineVariant: Color(0xFFF5EFF1),
    surfaceTint: Color(0xFFF49399),
  );

  /// rose 主题 AppColorsExtension
  /// info 用海盐薄荷（互补），category 跨粉/灰/薄荷
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF7FB4A0),
    onSuccess: Color(0xFF1B3A2F),
    successContainer: Color(0xFFD8ECE4),
    onSuccessContainer: Color(0xFF12352B),
    warning: Color(0xFFE0B36A),
    onWarning: Color(0xFF3F2D0E),
    warningContainer: Color(0xFFF5E6CE),
    onWarningContainer: Color(0xFF3A2810),
    info: Color(0xFF7CA9A4),
    onInfo: Color(0xFF1E3A36),
    infoContainer: Color(0xFFD8E9E5),
    onInfoContainer: Color(0xFF143B36),
    category: [
      Color(0xFFFECBCB), Color(0xFFF49399), Color(0xFFF1B3B8), Color(0xFF4A1F24),
      Color(0xFFEDD8DC), Color(0xFFA69297),
      Color(0xFF7CA9A4), Color(0xFFCDDDDD),
    ],
  );
}