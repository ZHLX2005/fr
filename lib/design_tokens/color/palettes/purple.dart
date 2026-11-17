// Layer 1 — Purple 主题调色板变量。

import 'package:flutter/material.dart';

import '../app_colors_extension.dart';

class PurpleColors {
  PurpleColors._();

  /// 暮紫主题（dark）— **银白月光**主色 + 近中性冷灰环境 + 稀用鎏金。
  ///
  /// 2026-10-12 重配（对齐 theme-color-cards 提案）：
  /// 去掉棕黑底 / 暖褐灰 secondary，避免紫+金+棕三族混浊。
  ///
  /// 2026-11-17 再配（反馈：「暮紫色这个紫色更加偏向银白月光色，紫色味道太重了」）：
  /// 只调**彩度与环境**，不换色相 —— 主色色相还是那束暮光（256°），
  /// 但 sat 从 37% 压到 18%、亮度从 74% 提到 79%，于是它读起来是
  /// 「月光打在银器上的那层白」，紫只剩一点点余光，而不是一块紫。
  ///
  /// 亮度特意压在 onSurface（#E9E7EE）之下：主色是**强调**，跟正文一样白
  /// 就分不出谁是"该看的那一处"了；比正文暗一档、比正文冷一档，才是月光。
  ///
  /// 环境色一起往中性挪：surface 原本 #1A1822（B 比 R 高 8，明显偏紫），
  /// 现在 #1B1B1F（只差 4/255，冷灰里透一丝紫）—— 底色不紫，主色那点紫才显得干净。
  /// 鎏金（tertiary）不动：它是「稀用强调」，紫退下去之后金色的分量刚好。
  static const ColorScheme scheme = ColorScheme(
    brightness: Brightness.dark,
    // 银白月光：H 256° · S 18% · L 79%（原 #B9A6D6 是 S 37% · L 74%）
    primary: Color(0xFFC6C1D4),
    onPrimary: Color(0xFF1A1720),
    // 容器仍是深一档的同色相，只把彩度压到和主色同一水平
    primaryContainer: Color(0xFF32313A),
    onPrimaryContainer: Color(0xFFEDEAF3),
    secondary: Color(0xFFA8A6B3),
    onSecondary: Color(0xFF1A1920),
    secondaryContainer: Color(0xFF2B2A33),
    onSecondaryContainer: Color(0xFFE4E2EA),
    tertiary: Color(0xFFD2BA7A),
    onTertiary: Color(0xFF1A1520),
    tertiaryContainer: Color(0xFF3F3520),
    onTertiaryContainer: Color(0xFFF0E2B8),
    surface: Color(0xFF1B1B1F),
    onSurface: Color(0xFFE9E7EE),
    onSurfaceVariant: Color(0xFFA19FAC),
    surfaceContainerHighest: Color(0xFF131316),
    error: Color(0xFFE090B0),
    onError: Color(0xFF1A1520),
    errorContainer: Color(0xFF6E3A52),
    onErrorContainer: Color(0xFFF5D4E4),
    outline: Color(0xFF393843),
    outlineVariant: Color(0xFF29282F),
    surfaceTint: Color(0xFFC6C1D4),
  );

  /// purple 主题 AppColorsExtension
  /// info 用鎏金（稀强调）；category 跨银白 / 金，不再掺棕灰
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
      Color(0xFFEDEAF3),
      Color(0xFFC6C1D4),
      Color(0xFFA8A6B3),
      Color(0xFF1B1B1F),
      Color(0xFFD2BA7A),
      Color(0xFF32313A),
      Color(0xFFE9E7EE),
      Color(0xFF131316),
    ],
  );
}
