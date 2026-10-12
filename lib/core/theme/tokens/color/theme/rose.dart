// Layer 1 — Rose 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class RoseColors {
  RoseColors._();

  /// 粉雾主题（light）—— 对照 TUTUMIYU 式「干净粉」参考图重配。
  ///
  /// 2026-10-12 参考设计图：
  ///   · 页面近白，粉不铺满（干净感来自留白，不是把粉降彩）
  ///   · primary = 尘玫瑰 CTA（加号钮 / 确认下单）≈ #C8828E
  ///   · primaryContainer = 浅腮红信息卡 ≈ #F5E4E8
  ///   · 扔掉海盐薄荷；强调留在粉家族
  ///   · 字色近黑，不用浊褐粉当正文
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFC8828E),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFF5E4E8),
    onPrimaryContainer: Color(0xFF5A3038),
    secondary: Color(0xFF9A8A8E),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF0E8EA),
    onSecondaryContainer: Color(0xFF3A3034),
    tertiary: Color(0xFFB56B78),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFF0D4DA),
    onTertiaryContainer: Color(0xFF4A2430),
    surface: Color(0xFFFFFCFA),
    onSurface: Color(0xFF2A2426),
    onSurfaceVariant: Color(0xFF8A7A7E),
    surfaceContainerHighest: Color(0xFFF5F0F1),
    error: Color(0xFFB04650),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFE8CCD0),
    onErrorContainer: Color(0xFF3F1518),
    outline: Color(0xFFE8DCE0),
    outlineVariant: Color(0xFFF0E8EA),
    surfaceTint: Color(0xFFC8828E),
  );

  /// rose 主题 AppColorsExtension
  /// info 用同族深尘玫瑰；category 跨白 / 腮红 / 尘玫瑰
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF7FB4A0),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD8ECE4),
    onSuccessContainer: Color(0xFF12352B),
    warning: Color(0xFFE0B36A),
    onWarning: Color(0xFF3F2D0E),
    warningContainer: Color(0xFFF5E6CE),
    onWarningContainer: Color(0xFF3A2810),
    info: Color(0xFFB56B78),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFF0D4DA),
    onInfoContainer: Color(0xFF4A2430),
    category: [
      Color(0xFFF5E4E8),
      Color(0xFFC8828E),
      Color(0xFFB56B78),
      Color(0xFF2A2426),
      Color(0xFF9A8A8E),
      Color(0xFFF5F0F1),
      Color(0xFFFFFCFA),
      Color(0xFF5A3038),
    ],
  );
}
