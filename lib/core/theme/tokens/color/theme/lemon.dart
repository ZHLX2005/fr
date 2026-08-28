// Layer 1 — Lemon 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class LemonColors {
  LemonColors._();

  /// 柠檬鼠尾草主题（light）—— 闲鱼风亮柠檬黄 + 鼠尾草绿互补撞色 + 纯白背景。
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFFFD54F),
    onPrimary: Color(0xFF37474F),
    primaryContainer: Color(0xFFFFF9C4),
    onPrimaryContainer: Color(0xFF37474F),
    secondary: Color(0xFF90A4AE),
    onSecondary: Color(0xFF37474F),
    secondaryContainer: Color(0xFFECEFF1),
    onSecondaryContainer: Color(0xFF263238),
    tertiary: Color(0xFF81C784),
    onTertiary: Color(0xFF1B5E20),
    tertiaryContainer: Color(0xFFE8F5E9),
    onTertiaryContainer: Color(0xFF1B5E20),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF37474F),
    onSurfaceVariant: Color(0xFF78909C),
    surfaceContainerHighest: Color(0xFFFFFDE7),
    error: Color(0xFFE57373),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFEBEE),
    onErrorContainer: Color(0xFFB71C1C),
    outline: Color(0xFFEAE5D6),
    outlineVariant: Color(0xFFF4F1E8),
    surfaceTint: Color(0xFFFFD54F),
  );

  /// lemon 主题 AppColorsExtension
  /// info 用鼠尾草绿（互补），category 跨柠檬黄/灰/绿
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF81C784),
    onSuccess: Color(0xFF1B5E20),
    successContainer: Color(0xFFE8F5E9),
    onSuccessContainer: Color(0xFF1B5E20),
    warning: Color(0xFFFFD54F),
    onWarning: Color(0xFF37474F),
    warningContainer: Color(0xFFFFF9C4),
    onWarningContainer: Color(0xFF37474F),
    info: Color(0xFF81C784),
    onInfo: Color(0xFF1B5E20),
    infoContainer: Color(0xFFE8F5E9),
    onInfoContainer: Color(0xFF1B5E20),
    category: [
      Color(0xFFFFF9C4), Color(0xFFFFD54F), Color(0xFF81C784), Color(0xFF1B5E20),
      Color(0xFF90A4AE), Color(0xFFE8F5E9),
      Color(0xFFFFFDE7), Color(0xFFA5D6A7),
    ],
  );
}