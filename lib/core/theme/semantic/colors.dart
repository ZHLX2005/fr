// Layer 2 — Semantic color tokens.
//
// zen / purple / ink 主题 ColorScheme 调色板。设计：v6.1「主色不动 · 环境染互补色温」——
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
// 墨白（ink）：墨黑主色 + 纯纸白底 + 墨赭（hue18°）作互补强调 + 章印朱红 error。

import 'package:flutter/material.dart';
import '../tokens/colors.dart';

/// zen / purple / ink 主题 ColorScheme 调色板。
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
    secondary: Color(0xFFA8A394), // 环境灰（鎏金档）
    onSecondary: Color(0xFF191713),
    secondaryContainer: Color(0xFF323029),
    onSecondaryContainer: Color(0xFFE7E3DA),
    tertiary: Color(0xFFC0A873), // 互补强调（鎏金）
    onTertiary: Color(0xFF1B1722),
    tertiaryContainer: Color(0xFFCBB88C),
    onTertiaryContainer: Color(0xFF3E3018),
    surface: Color(0xFF201F1A), // 鎏金暖黑底
    onSurface: Color(0xFFE3E2DD), // 暖墨浅字
    onSurfaceVariant: Color(0xFFA8A499),
    surfaceContainerHighest: Color(0xFF191713), // 抬升背景
    error: Color(0xFFC99DBA), // 红紫系保持
    onError: Color(0xFF1B1722),
    errorContainer: Color(0xFF8D6E82),
    onErrorContainer: Color(0xFFF2D9E8),
    outline: Color(0xFF3F3C34), // 环境深灰
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
    secondary: Color(0xFF8A8475),
    onSecondary: RawColors.pureWhite,
    secondaryContainer: Color(0xFFE9E7E2),
    onSecondaryContainer: Color(0xFF4C4533),
    tertiary: Color(0xFFA0594A),
    onTertiary: RawColors.pureWhite,
    tertiaryContainer: Color(0xFFB1776B),
    onTertiaryContainer: Color(0xFF4A1F14),
    surface: Color(0xFFFBF8F1),
    onSurface: Color(0xFF2C2C2C),
    onSurfaceVariant: Color(0xFF8A8475),
    surfaceContainerHighest: Color(0xFFF4F1EA),
    error: Color(0xFFA0594A),
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFAE7265),
    onErrorContainer: Color(0xFF4A1F14),
    outline: Color(0xFFD9D5C8),
    outlineVariant: Color(0xFFE8E6E3),
    surfaceTint: Color(0xFF7A9A7E),
  );

  /// 墨白主题（ink）— 墨黑主色 + 纯纸白底 + 墨赭互补强调。
  ///
  /// 纸墨语义：
  ///   primary       → 墨黑（笔锋）
  ///   surface       → 纯纸白（生宣底）
  ///   surfaceContainerHighest → 浅纸灰（抬升纸面）
  ///   onSurface     → 墨黑（墨字落纸）
  ///   onSurfaceVariant → 纸灰（弱字）
  ///   tertiary      → 墨赭（呼应纸墨章印）
  ///   error         → 章印朱红（保留危险语义）
  static const ColorScheme ink = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF1A1A1A), // 墨黑（笔锋）
    onPrimary: RawColors.pureWhite,
    primaryContainer: Color(0xFFE8E8E8), // 浅纸灰（笔触留白）
    onPrimaryContainer: Color(0xFF0D0D0D), // 深炭（浓墨）
    secondary: Color(0xFF6E6E6E), // 纸灰文字
    onSecondary: RawColors.pureWhite,
    secondaryContainer: Color(0xFFEEEEEE), // 浅纸边
    onSecondaryContainer: Color(0xFF1F1F1F),
    tertiary: Color(0xFF8C5A4F), // 互补强调（墨赭）
    onTertiary: RawColors.pureWhite,
    tertiaryContainer: Color(0xFFE5D2CB),
    onTertiaryContainer: Color(0xFF3F1F18),
    surface: Color(0xFFFAFAFA), // 纯纸白（生宣）
    onSurface: Color(0xFF1A1A1A), // 墨黑字
    onSurfaceVariant: Color(0xFF707070), // 纸灰字
    surfaceContainerHighest: Color(0xFFF0F0F0),
    error: Color(0xFFB04650), // 章印朱红
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFE8CCD0),
    onErrorContainer: Color(0xFF3F1518),
    outline: Color(0xFFD0D0D0), // 纸线
    outlineVariant: Color(0xFFE5E5E5),
    surfaceTint: Color(0xFF1A1A1A),
  );

  /// 粉雾海盐主题（rose）— 粉主色 ↔ 海盐薄荷互补撞色 + 纯白背景。
  ///
  /// 撞色设计：主色粉（Velvet Bloom）与互补薄荷绿形成 hue 173° 对比，纯白背景让撞色更突出。
  ///
  /// 角色映射：
  ///   primary           → Velvet Bloom（#F49399）：主按钮背景 / FAB / 选中 tab / 重点 CTA
  ///   onPrimary         → 深玫瑰棕（#3A2A2D）：主按钮文字 / 图标前景
  ///   primaryContainer  → Petal Sugar（#FECBCB）：浅粉容器 / 标签背景 / 次级按钮
  ///   onPrimaryContainer→ 深玫瑰棕（#4A1F24）：容器内文字 / 标签文字
  ///   secondary         → 粉雾灰（#A69297）：环境灰 / 次要图标
  ///   onSecondary       → 深玫瑰棕（#3A2A2D）：次要图标前景
  ///   secondaryContainer → Blush Mirage（#F1B3B8）：次级按钮 / 芯片 / 次标签
  ///   onSecondaryContainer→ 深玫瑰棕（#4A1F24）：芯片内文字
  ///   tertiary          → 海盐薄荷（#7CA9A4）：互补强调 / 图标高亮 / 链接 / 成功态
  ///   onTertiary         → 深薄荷绿（#1E3A36）：薄荷绿内文字 / 图标前景
  ///   tertiaryContainer  → 浅薄荷绿（#D8E9E5）：薄荷绿容器 / 浅强调背景
  ///   onTertiaryContainer→ 深薄荷绿（#143B36）：容器内文字
  ///   surface           → 纯白（#FFFFFF）：页面背景 / 卡片背景
  ///   onSurface         → 深玫瑰棕（#3A2A2D）：正文 / 标题文字
  ///   onSurfaceVariant  → 弱玫瑰灰（#8A6F74）：辅助文字 / 占位符
  ///   surfaceContainerHighest → Rose Fog（#EDD8DC）：页面底 / 抬升背景
  ///   error             → 玫印朱红（#B04650）：危险 / 错误提示
  ///   onError           → 纯白：错误文字
  ///   errorContainer    → 浅红紫（#E8CCD0）：错误背景 / 危险区
  ///   onErrorContainer  → 深玫瑰棕（#3F1518）：错误容器内文字
  ///   outline           → 浅薄荷绿（#B2DFDB）：分割线 / 边框 / 禁用态
  ///   outlineVariant    → 极浅薄荷（#E0F2F1）：次要分割线
  ///   surfaceTint       → Velvet Bloom（#F49399）：表面色调，用于抬升背景
  static const ColorScheme rose = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFF49399), // Velvet Bloom 主按钮/FAB/选中tab
    onPrimary: Color(0xFF3A2A2D), // 深玫瑰棕 主按钮文字/图标前景
    primaryContainer: Color(0xFFFECBCB), // Petal Sugar 浅粉容器/标签背景
    onPrimaryContainer: Color(0xFF4A1F24),
    secondary: Color(0xFFA69297), // 粉雾灰 环境灰/次要图标
    onSecondary: Color(0xFF3A2A2D),
    secondaryContainer: Color(0xFFF1B3B8), // Blush Mirage 次级按钮/芯片
    onSecondaryContainer: Color(0xFF4A1F24),
    tertiary: Color(0xFF7CA9A4), // 海盐薄荷 互补强调/图标高亮/链接
    onTertiary: Color(0xFF1E3A36),
    tertiaryContainer: Color(0xFFD8E9E5),
    onTertiaryContainer: Color(0xFF143B36),
    surface: Color(0xFFFFFFFF), // 纯白 页面背景/卡片背景
    onSurface: Color(0xFF3A2A2D), // 深玫瑰棕 正文/标题文字
    onSurfaceVariant: Color(0xFF8A6F74), // 弱玫瑰灰 辅助文字/占位符
    surfaceContainerHighest: Color(0xFFEDD8DC), // Rose Fog 页面底/抬升背景
    error: Color(0xFFB04650), // 玫印朱红 危险/错误提示
    onError: RawColors.pureWhite,
    errorContainer: Color(0xFFE8CCD0),
    onErrorContainer: Color(0xFF3F1518),
    outline: Color(0xFFEADEE1), // 淡粉白 分割线/边框/禁用态（呼应主题设置色点的低调描边）
    outlineVariant: Color(0xFFF5EFF1), // 极淡粉白 次要分割线
    surfaceTint: Color(0xFFF49399),
  );

  /// 柠檬鼠尾草主题（lemon）— 闲鱼风亮柠檬黄 ↔ 鼠尾草绿互补撞色 + 纯白背景。
  ///
  /// 撞色设计：亮柠檬黄与鼠尾草绿形成清新对比，纯白背景让配色更活泼年轻。
  ///
  /// 角色映射：
  ///   primary           → 亮柠檬黄（#FFD54F）：主按钮背景 / FAB / 选中 tab / 标题点缀
  ///   primaryContainer  → 浅柠檬黄（#FFF9C4）：容器底色 / 卡片底色 / 标签背景
  ///   tertiary          → 鼠尾草绿（#81C784）：互补强调 / 图标高亮 / 链接 / 成功态
  ///   tertiaryContainer → 浅绿容器（#E8F5E9）：卡片点缀 / 浅强调背景
  ///   surfaceContainerHighest → 极浅灰黄（#FFFDE7）：AppBar 导航条背景
  ///   surface           → 纯白（#FFFFFF）：页面背景 / 卡片背景
  ///   onSurfaceVariant  → #78909C：蓝灰弱字 / 辅助
  static const ColorScheme lemon = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFFFD54F), // 亮柠檬黄 主按钮/FAB/选中tab/标题点缀
    onPrimary: Color(0xFF37474F), // 深蓝灰 主按钮文字/图标前景
    primaryContainer: Color(0xFFFFF9C4), // 浅柠檬黄 容器底色/卡片底色/标签背景
    onPrimaryContainer: Color(0xFF37474F), // 深蓝灰 容器内文字/标签文字
    secondary: Color(0xFF90A4AE), // 蓝灰 环境灰/次要图标/分割线
    onSecondary: Color(0xFF37474F), // 深蓝灰 次要图标前景
    secondaryContainer: Color(0xFFECEFF1), // 浅蓝灰 次级容器/辅助背景
    onSecondaryContainer: Color(0xFF263238), // 深蓝灰 辅助容器内文字
    tertiary: Color(0xFF81C784), // 鼠尾草绿 互补强调/图标高亮/链接/成功态
    onTertiary: Color(0xFF1B5E20), // 深绿 鼠尾草绿内文字/图标前景
    tertiaryContainer: Color(0xFFE8F5E9), // 浅绿容器 浅强调背景/标签/卡片点缀
    onTertiaryContainer: Color(0xFF1B5E20), // 深绿 浅绿容器内文字
    surface: Color(0xFFFFFFFF), // 纯白 页面背景/卡片背景
    onSurface: Color(0xFF37474F), // 深蓝灰 正文/标题文字
    onSurfaceVariant: Color(0xFF78909C), // 蓝灰 辅助文字/占位符/弱图标
    surfaceContainerHighest: Color(0xFFFFFDE7), // 极浅灰黄 AppBar导航条背景/抬升背景
    error: Color(0xFFE57373), // 柔和红 危险/错误提示
    onError: RawColors.pureWhite, // 纯白 错误文字
    errorContainer: Color(0xFFFFEBEE), // 浅红 错误背景/危险区
    onErrorContainer: Color(0xFFB71C1C), // 深红 错误容器内文字
    outline: Color(0xFFEAE5D6), // 淡柠檬暖白 分割线/边框/禁用态描边（呼应主题设置色点的低调描边）
    outlineVariant: Color(0xFFF4F1E8), // 极淡柠檬白 次要分割线/抬升背景
    surfaceTint: Color(0xFFFFD54F), // 亮柠檬黄 表面色调
  );
}
