// Layer 2 — Semantic extensions.
//
// 状态色（success/warning/info）+ 分类色板（8 色）作为 ThemeExtension。
// 在 widget 中通过 `Theme.of(context).extension<AppColorsExtension>()`
// 读取。原料色优先引用 ../tokens/colors.dart 的 RawColors。
//
// 设计意图：ColorScheme 是 M3 标准角色（primary/secondary/...），
// AppColorsExtension 是应用扩展角色（success/category/...）。
//
// v6.1 改动：category 8 色板由"单族同色"改为"主色+环境+互补"三族混排，
// 与主页"主色 vs 环境色温互补"结构一致；info 用 tertiary 互补色族。

import 'package:flutter/material.dart';

/// 应用扩展色板 — 状态色（success/warning/info/error）+ 分类色板（8 色）。
///
/// 在 widget 中通过 `Theme.of(context).extension<AppColorsExtension>()` 读取。
/// 用于图表、标签分类、优先级等需要色彩多样性的场景，
/// 且所有色已对齐主题低饱和度。
@immutable
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;
  final List<Color> category;

  const AppColorsExtension({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.category,
  });

  @override
  AppColorsExtension copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
    List<Color>? category,
  }) {
    return AppColorsExtension(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      category: category ?? this.category,
    );
  }

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsExtension(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      info: l(info, other.info),
      onInfo: l(onInfo, other.onInfo),
      infoContainer: l(infoContainer, other.infoContainer),
      onInfoContainer: l(onInfoContainer, other.onInfoContainer),
      category: List.generate(
        category.length,
        (i) => l(category[i], other.category[i]),
      ),
    );
  }
}

/// 茶禅主题对应的 AppColorsExtension 调色板。
///
/// v6.1：category 8 色板混合主色族（4 档浅深）+ 环境色族（2 档）+ 互补色族（2 档），
/// 让分类调色板跨色域，匹配主页"主色 vs 环境色温互补"的视觉语言。
class ThemeAppColors {
  ThemeAppColors._();

  /// 茶禅主题（zen）— category 跨绿/暖灰/陶土红（范本，原结构保留）。
  static const AppColorsExtension zen = AppColorsExtension(
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
