// Layer 1 — Cobalt 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class CobaltColors {
  CobaltColors._();

  /// 宝蓝主题（light）—— 对照 ID'CAKE 式「宝蓝 + 纯白」高对比参考图。
  ///
  /// 结构：
  ///   · primary = 宝蓝品牌底 / CTA / 线稿图标 ≈ #163A94
  ///   · surface = 纯白卡片（主内容面）
  ///   · 页面可用 Scaffold(backgroundColor: primary) 做出启动屏/顶栏蓝底
  ///   · 近单色：tertiary 同族稍亮蓝，不用第二强调色搅浑
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF163A94),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD9E3F7),
    onPrimaryContainer: Color(0xFF0C2048),
    secondary: Color(0xFF6B7A96),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE4E8F0),
    onSecondaryContainer: Color(0xFF1E2838),
    tertiary: Color(0xFF3D5AAD),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFD0DAF2),
    onTertiaryContainer: Color(0xFF142448),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1A1A1A),
    onSurfaceVariant: Color(0xFF5A6578),
    surfaceContainerHighest: Color(0xFFEEF1F7),
    error: Color(0xFFB04650),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFE8CCD0),
    onErrorContainer: Color(0xFF3F1518),
    outline: Color(0xFFC8D0E0),
    outlineVariant: Color(0xFFE4E8F0),
    surfaceTint: Color(0xFF163A94),
  );

  /// cobalt 主题 AppColorsExtension
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF3D8F6E),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFD0E8DC),
    onSuccessContainer: Color(0xFF0E3324),
    warning: Color(0xFFD4A24A),
    onWarning: Color(0xFF2C2210),
    warningContainer: Color(0xFFF5E6CE),
    onWarningContainer: Color(0xFF3A2810),
    info: Color(0xFF3D5AAD),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFD0DAF2),
    onInfoContainer: Color(0xFF142448),
    category: [
      Color(0xFFD9E3F7),
      Color(0xFF163A94),
      Color(0xFF3D5AAD),
      Color(0xFF1A1A1A),
      Color(0xFF6B7A96),
      Color(0xFFEEF1F7),
      Color(0xFFFFFFFF),
      Color(0xFF0C2048),
    ],
  );
}
