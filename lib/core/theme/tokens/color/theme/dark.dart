// Layer 1 — Dark 主题调色板变量（第 7 套「暗黑」）。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class DarkColors {
  DarkColors._();

  /// 暗黑主题（dark）— 中性石墨无彩系，OLED 友好，内容优先。
  ///
  /// 2026-10-13 提案落码（对照 temp/theme-dark-mode-prototype.html）：
  /// 与暮紫（冷紫 + 鎏金）区隔——本套无色彩倾向，secondary/tertiary 均为
  /// 中性灰系，error 用去饱和柔红。surfaceContainerHighest #0C0C0A 贴近纯黑。
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFC9C5BD),
    onPrimary: Color(0xFF1B1A17),
    primaryContainer: Color(0xFF37352F),
    onPrimaryContainer: Color(0xFFECEAE3),
    secondary: Color(0xFF9C9992),
    onSecondary: Color(0xFF1C1B19),
    secondaryContainer: Color(0xFF302F2B),
    onSecondaryContainer: Color(0xFFE8E6DF),
    tertiary: Color(0xFFB5B2AA),
    onTertiary: Color(0xFF1D1C19),
    tertiaryContainer: Color(0xFF3A3833),
    onTertiaryContainer: Color(0xFFEFEDE6),
    surface: Color(0xFF131311),
    onSurface: Color(0xFFE8E7E3),
    onSurfaceVariant: Color(0xFF9B9A95),
    surfaceContainerHighest: Color(0xFF0C0C0A),
    error: Color(0xFFD98D8D),
    onError: Color(0xFF241212),
    errorContainer: Color(0xFF5E3232),
    onErrorContainer: Color(0xFFF6DCDC),
    outline: Color(0xFF34332F),
    outlineVariant: Color(0xFF242320),
    surfaceTint: Color(0xFFC9C5BD),
  );

  /// dark 主题 AppColorsExtension
  /// graphite 无彩规则衍生：success/warning/info 走去饱和灰调（灰绿 / 灰琥珀 /
  /// 灰蓝），保留语义可辨但不破坏无彩环境；category 沿用暮紫的结构位
  /// （onPrimaryContainer/primary/secondary/surface/tertiary/primaryContainer/
  /// onSurface/surfaceContainerHighest），逐位换成石墨系。
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF9AB8A6),
    onSuccess: Color(0xFF14201A),
    successContainer: Color(0xFF26332C),
    onSuccessContainer: Color(0xFFC2D8CB),
    warning: Color(0xFFC7B489),
    onWarning: Color(0xFF1F1B12),
    warningContainer: Color(0xFF3A3320),
    onWarningContainer: Color(0xFFE8DCC0),
    info: Color(0xFF9AA8B5),
    onInfo: Color(0xFF14181D),
    infoContainer: Color(0xFF28303A),
    onInfoContainer: Color(0xFFD2DCE5),
    category: [
      Color(0xFFECEAE3),
      Color(0xFFC9C5BD),
      Color(0xFF9C9992),
      Color(0xFF131311),
      Color(0xFFB5B2AA),
      Color(0xFF37352F),
      Color(0xFFE8E7E3),
      Color(0xFF0C0C0A),
    ],
  );
}
