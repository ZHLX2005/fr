// Layer 1 — Zen 主题调色板变量（5 套 ColorScheme + 5 套 AppColorsExtension）。
//
// 主题色全部集中在此 hex 文件，strategy/themes/zen.dart 引用 ZenColors.scheme/scheme 即可。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class ZenColors {
  ZenColors._();

  /// 茶禅主题（zen）—— sage 绿 ↔ 暖米环境（hue42°，范本）。
  ///
  /// ZenColors 7 个常量完整映射：
  ///   sage       → primary
  ///   ink        → onSurface
  ///   bg         → surfaceContainerHighest
  ///   surface    → surface
  ///   secondary  → onSurfaceVariant
  ///   hair       → outline
  ///   mutedRed   → tertiary / error
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF7A9A7E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE8F0E5),
    onPrimaryContainer: Color(0xFF2D4A2A),
    secondary: Color(0xFF8A8475),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE9E7E2),
    onSecondaryContainer: Color(0xFF4C4533),
    tertiary: Color(0xFFA0594A),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFB1776B),
    onTertiaryContainer: Color(0xFF4A1F14),
    surface: Color(0xFFFBF8F1),
    onSurface: Color(0xFF2C2C2C),
    onSurfaceVariant: Color(0xFF8A8475),
    surfaceContainerHighest: Color(0xFFF4F1EA),
    error: Color(0xFFA0594A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFAE7265),
    onErrorContainer: Color(0xFF4A1F14),
    outline: Color(0xFFD9D5C8),
    outlineVariant: Color(0xFFE8E6E3),
    surfaceTint: Color(0xFF7A9A7E),
  );

  /// zen 主题 AppColorsExtension 调色板（状态色 + 分类色板）
  /// category 跨绿/暖灰/陶土红（范本，原结构保留）
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF84BD9C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDEEDE4),
    onSuccessContainer: Color(0xFF1F3F26),
    warning: Color(0xFFC2AD8E),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF0ECE5),
    onWarningContainer: Color(0xFF3F2D14),
    info: Color(0xFF7A9A7E),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFE8F0E5),
    onInfoContainer: Color(0xFF2D4A2A),
    category: [
      Color(0xFF7A9A7E), Color(0xFF8A8475), Color(0xFFA0594A), Color(0xFFD9D5C8),
      Color(0xFF6F6A60), Color(0xFF2C2C2C), Color(0xFFE8F0E5), Color(0xFFA0594A),
    ],
  );
}