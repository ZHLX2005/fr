// Layer 1 — Purple 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class PurpleColors {
  PurpleColors._();

  /// 暮紫主题（dark）— 暮紫主色 ↔ 鎏金暖黑环境（hue45°）。
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFAB97BF),
    onPrimary: Color(0xFF1B1722),
    primaryContainer: Color(0xFF3D2E5C),
    onPrimaryContainer: Color(0xFFE0DAF0),
    secondary: Color(0xFFA8A394),
    onSecondary: Color(0xFF191713),
    secondaryContainer: Color(0xFF323029),
    onSecondaryContainer: Color(0xFFE7E3DA),
    tertiary: Color(0xFFC0A873),
    onTertiary: Color(0xFF1B1722),
    tertiaryContainer: Color(0xFFCBB88C),
    onTertiaryContainer: Color(0xFF3E3018),
    surface: Color(0xFF201F1A),
    onSurface: Color(0xFFE3E2DD),
    onSurfaceVariant: Color(0xFFA8A499),
    surfaceContainerHighest: Color(0xFF191713),
    error: Color(0xFFC99DBA),
    onError: Color(0xFF1B1722),
    errorContainer: Color(0xFF8D6E82),
    onErrorContainer: Color(0xFFF2D9E8),
    outline: Color(0xFF3F3C34),
    outlineVariant: Color(0xFF34322D),
    surfaceTint: Color(0xFFAB97BF),
  );

  /// purple 主题 AppColorsExtension
  /// info 用鎏金（互补），category 跨紫/金/金
  static const AppColorsExtension appColors = AppColorsExtension(
    success: Color(0xFF95B89E),
    onSuccess: Color(0xFF1B1722),
    successContainer: Color(0xFF2A3F30),
    onSuccessContainer: Color(0xFFB8D6BE),
    warning: Color(0xFFD4B68E),
    onWarning: Color(0xFF1B1722),
    warningContainer: Color(0xFF4A3D24),
    onWarningContainer: Color(0xFFF0D9A8),
    info: Color(0xFFC0A873),
    onInfo: Color(0xFF1B1722),
    infoContainer: Color(0xFF3D3423),
    onInfoContainer: Color(0xFFF0D9A8),
    category: [
      Color(0xFFE6E0EC), Color(0xFFAB97BF), Color(0xFFD1C6DC), Color(0xFF1F1B22),
      Color(0xFFA8A394), Color(0xFFC0A873), Color(0xFFECE5D5), Color(0xFF231E15),
    ],
  );
}