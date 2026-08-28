// Layer 1 — Ink 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class InkColors {
  InkColors._();

  /// 墨白主题（light）—— 墨黑主色 + 纯纸白底 + 墨赭互补强调。
  ///
  /// 纸墨语义：
  ///   primary       → 墨黑（笔锋）
  ///   surface       → 纯纸白（生宣底）
  ///   surfaceContainerHighest → 浅纸灰（抬升纸面）
  ///   onSurface     → 墨黑（墨字落纸）
  ///   onSurfaceVariant → 纸灰（弱字）
  ///   tertiary      → 墨赭（呼应纸墨章印）
  ///   error         → 章印朱红（保留危险语义）
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1A1A1A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE8E8E8),
    onPrimaryContainer: Color(0xFF0D0D0D),
    secondary: Color(0xFF6E6E6E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEEEEEE),
    onSecondaryContainer: Color(0xFF1F1F1F),
    tertiary: Color(0xFF8C5A4F),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE5D2CB),
    onTertiaryContainer: Color(0xFF3F1F18),
    surface: Color(0xFFFAFAFA),
    onSurface: Color(0xFF1A1A1A),
    onSurfaceVariant: Color(0xFF707070),
    surfaceContainerHighest: Color(0xFFF0F0F0),
    error: Color(0xFFB04650),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFE8CCD0),
    onErrorContainer: Color(0xFF3F1518),
    outline: Color(0xFFD0D0D0),
    outlineVariant: Color(0xFFE5E5E5),
    surfaceTint: Color(0xFF1A1A1A),
  );

  /// ink 主题 AppColorsExtension
  /// info 用墨色呼应主色，category 跨白/黑/纸灰/墨赭/朱印
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF8AAD94),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD8E4DC),
    onSuccessContainer: Color(0xFF1F3326),
    warning: Color(0xFFA89377),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFE0DBCF),
    onWarningContainer: Color(0xFF3F2D14),
    info: Color(0xFF1A1A1A),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFE0E0E0),
    onInfoContainer: Color(0xFF0D0D0D),
    category: [
      Color(0xFFE8E8E8), Color(0xFF1A1A1A), Color(0xFFB0B0B0), Color(0xFF0D0D0D),
      Color(0xFF707070), Color(0xFF8C5A4F), Color(0xFFE0E0E0), Color(0xFF2A2A2A),
    ],
  );
}