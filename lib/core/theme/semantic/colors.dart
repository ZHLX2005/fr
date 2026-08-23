// Layer 2 — Semantic color tokens.
//
// zen / purple 主题 ColorScheme 调色板。设计：v6.1「主色不动 · 环境染互补色温」——
//   · 主色族（原色不变）：primary / primaryContainer / 强调
//   · 环境族（按互补 hue 重新染色）：bg / surface / outline / onSurface /
//     onSurfaceVariant / secondary（环境灰）
//   · 互补强调族（新）：tertiary = 主色互补色
//   · error 红色保持不变（危险语义）
//
// 原料色优先引用 ../tokens/colors.dart 的 RawColors。
//
// 色温互补：环境 hue 与主色 hue 差约 150°~170°，形成整页色温对比。
// 茶禅范本（zen）：sage 绿（hue128°）漂在暖米环境（hue42°）。
// 暮紫（purple）：暮紫主色（hue275°）漂在鎏金暖黑环境（hue45°）。

import 'package:flutter/material.dart';
import '../tokens/colors.dart';

/// zen / purple 主题 ColorScheme 调色板。
///
/// onPrimary/onError 等纯黑/纯白优先引用 [RawColors]（tokens 层）。
class ThemeColorSchemes {
  ThemeColorSchemes._();

  /// 暮紫主题（深色）— 暮紫主色 ↔ 鎏金暖黑环境（hue45°）。
  static const ColorScheme purple = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFAB97BF),
    onPrimary: Color(0xFF1B1722),
    primaryContainer: Color(0xFF3D2E5C),
    onPrimaryContainer: Color(0xFFE0DAF0),
    secondary: Color(0xFFA8A394),                // 环境灰（鎏金档）
    onSecondary: Color(0xFF191713),
    secondaryContainer: Color(0xFF323029),
    onSecondaryContainer: Color(0xFFE7E3DA),
    tertiary: Color(0xFFC0A873),                // 互补强调（鎏金）
    onTertiary: Color(0xFF1B1722),
    tertiaryContainer: Color(0xFFCBB88C),
    onTertiaryContainer: Color(0xFF3E3018),
    surface: Color(0xFF201F1A),                // 鎏金暖黑底
    onSurface: Color(0xFFE3E2DD),                // 暖墨浅字
    onSurfaceVariant: Color(0xFFA8A499),
    surfaceContainerHighest: Color(0xFF191713),
    error: Color(0xFFC99DBA),                    // 红紫系保持
    onError: Color(0xFF1B1722),
    errorContainer: Color(0xFF8D6E82),
    onErrorContainer: Color(0xFFF2D9E8),
    outline: Color(0xFF3F3C34),                // 环境深灰
    outlineVariant: Color(0xFF34322D),
    surfaceTint: Color(0xFFAB97BF),
  );

  /// 茶禅主题（zen）— sage 绿 ↔ 暖米环境（hue42°，范本）。
  ///
  /// ZenColors 7 个常量完整映射：
  ///   sage       → primary
  ///   ink        → onSurface
  ///   bg         → surfaceContainerHighest
  ///   surface    → surface
  ///   secondary  → onSurfaceVariant
  ///   hair       → outline
  ///   mutedRed   → tertiary / error
  static const ColorScheme zen = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF7A9A7E),
    onPrimary: RawColors.pureWhite,
    primaryContainer: Color(0xFFE8F0E5),
    onPrimaryContainer: Color(0xFF2D4A2A),
    secondary: Color(0xFF9A927E),
    onSecondary: RawColors.pureWhite,
    secondaryContainer: Color(0xFFE9E7E2),
    onSecondaryContainer: Color(0xFF4C4533),
    tertiary: Color(0xFFA0594A),
    onTertiary: RawColors.pureWhite,
    tertiaryContainer: Color(0xFFB1776B),
    onTertiaryContainer: Color(0xFF4A1F14),
    surface: Color(0xFFFAF9F7),
    onSurface: Color(0xFF252118),
    onSurfaceVariant: Color(0xFF706A5C),
    surfaceContainerHighest: Color(0xFFF3F2EE),
    error: Color(0xFFA0594A),
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFAE7265),
    onErrorContainer: Color(0xFF4A1F14),
    outline: Color(0xFFDCD8D0),
    outlineVariant: Color(0xFFE8E6E3),
    surfaceTint: Color(0xFF7A9A7E),
  );
}
