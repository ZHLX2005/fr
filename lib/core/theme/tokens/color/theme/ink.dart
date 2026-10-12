// Layer 1 — Ink 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class InkColors {
  InkColors._();

  /// 墨白主题（light）—— 墨黑主色 + 暖生宣纸底 + 清晰章印朱红。
  ///
  /// 2026-10-12 重配（theme-color-cards 提案通过）：
  /// 冷白纸 + 浊赭 → 暖纸灰环境 + 清晰朱红 tertiary，去掉脏灰感。
  ///
  /// 纸墨语义：
  ///   primary       → 墨黑（笔锋）
  ///   surface       → 暖生宣
  ///   surfaceContainerHighest → 浅暖纸灰（托盘）
  ///   tertiary      → 章印朱红（稀强调）
  ///   error         → 章印朱红族
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1A1A1A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE8E4DE),
    onPrimaryContainer: Color(0xFF141210),
    secondary: Color(0xFF7A756E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFEAE6E0),
    onSecondaryContainer: Color(0xFF2A2622),
    tertiary: Color(0xFFC45C4A),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF0D8D2),
    onTertiaryContainer: Color(0xFF4A1F18),
    surface: Color(0xFFF7F5F2),
    onSurface: Color(0xFF1A1A1A),
    onSurfaceVariant: Color(0xFF6B6560),
    surfaceContainerHighest: Color(0xFFEEEBE6),
    error: Color(0xFFB04650),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFE8CCD0),
    onErrorContainer: Color(0xFF3F1518),
    outline: Color(0xFFDDD8D0),
    outlineVariant: Color(0xFFEAE6E0),
    surfaceTint: Color(0xFF1A1A1A),
  );

  /// ink 主题 AppColorsExtension
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF6E9B7C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD8E4DC),
    onSuccessContainer: Color(0xFF1F3326),
    warning: Color(0xFFB8956A),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFE8DFD0),
    onWarningContainer: Color(0xFF3F2D14),
    info: Color(0xFF1A1A1A),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFE8E4DE),
    onInfoContainer: Color(0xFF141210),
    category: [
      Color(0xFFE8E4DE),
      Color(0xFF1A1A1A),
      Color(0xFF7A756E),
      Color(0xFFF7F5F2),
      Color(0xFFC45C4A),
      Color(0xFFEEEBE6),
      Color(0xFF6B6560),
      Color(0xFF2A2622),
    ],
  );
}
