// Layer 2 — Semantic color tokens.
//
// 8 套主题 ColorScheme 调色板。设计：v6.1「主色不动 · 环境染互补色温」——
//   · 主色族（原色不变）：primary / primaryContainer / 强调
//   · 环境族（按互补 hue 重新染色）：bg / surface / outline / onSurface /
//     onSurfaceVariant / secondary（环境灰）
//   · 互补强调族（新）：tertiary = 主色互补色
//   · error 红色保持不变（危险语义）
//
// 原料色优先引用 ../tokens/colors.dart 的 RawColors，
// 主题专属色（蓝/粉/绿/橙/玫/紫/暮紫/茶禅）独立在本文件声明。
//
// 色温互补：每套的"环境 hue"和"主色 hue"差约 150°~170°，形成整页色温对比。
// 茶禅范本（zen）：sage 绿（hue128°）漂在暖米环境（hue42°）——
// 蓝/粉/绿/橙/玫/紫/暮紫 各取自家主色 hue 的互补，作为环境色温。

import 'package:flutter/material.dart';
import '../tokens/colors.dart';

/// 8 套主题 ColorScheme 调色板。
///
/// 每个 static 都是完整的 ColorScheme，可直接给 ThemeData.colorScheme 使用。
/// onPrimary/onError 等纯黑/纯白优先引用 [RawColors]（tokens 层）。
class ThemeColorSchemes {
  ThemeColorSchemes._();

  /// 墨青主题（浅色）— 墨蓝主色 ↔ 暖米环境（hue38°）。
  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF82A1BF),
    onPrimary: RawColors.pureWhite,
    primaryContainer: Color(0xFFECF0F4),
    onPrimaryContainer: Color(0xFF1F3A5C),
    secondary: Color(0xFF9A907E),                // 环境灰（暖米档）
    onSecondary: RawColors.pureWhite,
    secondaryContainer: Color(0xFFE9E6E2),
    onSecondaryContainer: Color(0xFF4C4333),
    tertiary: Color(0xFFBE9478),                // 互补强调（陶橙）
    onTertiary: RawColors.pureWhite,
    tertiaryContainer: Color(0xFFCAA790),
    onTertiaryContainer: Color(0xFF4A2E1E),
    surface: Color(0xFFFAF9F7),                // 环境染暖米
    onSurface: Color(0xFF252018),                // 环境深字（暖墨）
    onSurfaceVariant: Color(0xFF70695C),        // 环境灰
    surfaceContainerHighest: Color(0xFFF3F2EE), // = bg env
    error: Color(0xFFB6887C),                    // 红系保持
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFC19A90),
    onErrorContainer: Color(0xFF4A1F14),
    outline: Color(0xFFDCD8D0),                // 环境灰边框
    outlineVariant: Color(0xFFE8E6E3),
    surfaceTint: Color(0xFF82A1BF),
  );

  /// 夜间主题（深色）— 深蓝主色 ↔ 棕炭暖环境（hue35°）。
  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF9AADC1),
    onPrimary: Color(0xFF0F1419),
    primaryContainer: Color(0xFF2D3748),
    onPrimaryContainer: Color(0xFFCBD5E1),
    secondary: Color(0xFFA8A094),                // 环境灰（暖棕档）
    onSecondary: Color(0xFF191613),
    secondaryContainer: Color(0xFF322F29),
    onSecondaryContainer: Color(0xFFE7E1DA),
    tertiary: Color(0xFFC49B7C),                // 互补强调（暖橙）
    onTertiary: Color(0xFF0F1419),
    tertiaryContainer: Color(0xFFCFAD94),
    onTertiaryContainer: Color(0xFF4A301C),
    surface: Color(0xFF201E1A),                // 棕炭底
    onSurface: Color(0xFFE3E1DD),                // 暖墨浅字
    onSurfaceVariant: Color(0xFFA8A299),        // 环境灰
    surfaceContainerHighest: Color(0xFF191613),
    error: Color(0xFFC99286),                    // 红系保持
    onError: Color(0xFF0F1419),
    errorContainer: Color(0xFF8D665E),
    onErrorContainer: Color(0xFFF0CCC2),
    outline: Color(0xFF3F3A34),                // 环境深灰
    outlineVariant: Color(0xFF34312D),
    surfaceTint: Color(0xFF9AADC1),
  );

  /// 茶玫主题（浅色）— 玫粉主色 ↔ 青绿环境（hue155°）。
  static const ColorScheme pink = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFDEB5BD),
    onPrimary: RawColors.pureWhite,
    primaryContainer: Color(0xFFF7EEEF),
    onPrimaryContainer: Color(0xFF5A2233),
    secondary: Color(0xFF7E9A8F),                // 环境灰（青绿档）
    onSecondary: RawColors.pureWhite,
    secondaryContainer: Color(0xFFE2E9E6),
    onSecondaryContainer: Color(0xFF334C42),
    tertiary: Color(0xFF6FA58C),                // 互补强调（青绿）
    onTertiary: RawColors.pureWhite,
    tertiaryContainer: Color(0xFF89B5A1),
    onTertiaryContainer: Color(0xFF1F3A2A),
    surface: Color(0xFFF7FAF9),                // 青绿环境染
    onSurface: Color(0xFF182520),                // 冷墨字
    onSurfaceVariant: Color(0xFF5C7068),
    surfaceContainerHighest: Color(0xFFEEF3F1),
    error: Color(0xFFB6887C),                    // 红系保持
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFC19A90),
    onErrorContainer: Color(0xFF4A1F14),
    outline: Color(0xFFD0DCD7),                // 环境灰边框
    outlineVariant: Color(0xFFE3E8E6),
    surfaceTint: Color(0xFFDEB5BD),
  );

  /// 苔绿主题（浅色）— 苔绿主色 ↔ 玫紫环境（hue325°）。
  static const ColorScheme green = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF8AB276),
    onPrimary: RawColors.pureWhite,
    primaryContainer: Color(0xFFEEF4EC),
    onPrimaryContainer: Color(0xFF213F1A),
    secondary: Color(0xFF9A7E8F),                // 环境灰（玫紫档）
    onSecondary: RawColors.pureWhite,
    secondaryContainer: Color(0xFFE9E2E6),
    onSecondaryContainer: Color(0xFF4C3342),
    tertiary: Color(0xFFB58CA6),                // 互补强调（玫紫）
    onTertiary: RawColors.pureWhite,
    tertiaryContainer: Color(0xFFC2A1B6),
    onTertiaryContainer: Color(0xFF3E2A38),
    surface: Color(0xFFFAF7F9),                // 玫紫环境染
    onSurface: Color(0xFF251820),                // 冷墨字
    onSurfaceVariant: Color(0xFF705C68),
    surfaceContainerHighest: Color(0xFFF3EEF1),
    error: Color(0xFFB6887C),                    // 红系保持
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFC19A90),
    onErrorContainer: Color(0xFF4A1F14),
    outline: Color(0xFFDCD0D7),                // 环境灰边框
    outlineVariant: Color(0xFFE8E3E6),
    surfaceTint: Color(0xFF8AB276),
  );

  /// 陶橙主题（浅色）— 陶橙主色 ↔ 蓝调环境（hue212°）。
  static const ColorScheme orange = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFDEB8A6),
    onPrimary: RawColors.pureWhite,
    primaryContainer: Color(0xFFF8F0ED),
    onPrimaryContainer: Color(0xFF4F2A14),
    secondary: Color(0xFF7E8B9A),                // 环境灰（蓝调档）
    onSecondary: RawColors.pureWhite,
    secondaryContainer: Color(0xFFE2E5E9),
    onSecondaryContainer: Color(0xFF333F4C),
    tertiary: Color(0xFF7C9BB8),                // 互补强调（雾蓝）
    onTertiary: RawColors.pureWhite,
    tertiaryContainer: Color(0xFF94ADC5),
    onTertiaryContainer: Color(0xFF23304A),
    surface: Color(0xFFF7F9FA),                // 蓝调环境染
    onSurface: Color(0xFF181E25),                // 冷墨字
    onSurfaceVariant: Color(0xFF5C6570),
    surfaceContainerHighest: Color(0xFFEEF1F3),
    error: Color(0xFFB6887C),                    // 红系保持
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFC19A90),
    onErrorContainer: Color(0xFF4A1F14),
    outline: Color(0xFFD0D6DC),                // 环境灰边框
    outlineVariant: Color(0xFFE3E5E8),
    surfaceTint: Color(0xFFDEB8A6),
  );

  /// 玫紫主题（浅色）— 玫主色 ↔ 苔绿环境（hue110°）。
  static const ColorScheme rose = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFD9ABB6),
    onPrimary: RawColors.pureWhite,
    primaryContainer: Color(0xFFF7EEF0),
    onPrimaryContainer: Color(0xFF4A1F2A),
    secondary: Color(0xFF839A7E),                // 环境灰（苔绿档）
    onSecondary: RawColors.pureWhite,
    secondaryContainer: Color(0xFFE3E9E2),
    onSecondaryContainer: Color(0xFF374C33),
    tertiary: Color(0xFF73996E),                // 互补强调（苔绿）
    onTertiary: RawColors.pureWhite,
    tertiaryContainer: Color(0xFF8CAB88),
    onTertiaryContainer: Color(0xFF22381E),
    surface: Color(0xFFF8FAF7),                // 苔绿环境染
    onSurface: Color(0xFF1B2518),                // 冷墨字
    onSurfaceVariant: Color(0xFF5F705C),
    surfaceContainerHighest: Color(0xFFEFF3EE),
    error: Color(0xFFB6887C),                    // 红系保持
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFC19A90),
    onErrorContainer: Color(0xFF4A1F14),
    outline: Color(0xFFD2DCD0),                // 环境灰边框
    outlineVariant: Color(0xFFE4E8E3),
    surfaceTint: Color(0xFFD9ABB6),
  );

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