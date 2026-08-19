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

/// 8 套主题对应的 AppColorsExtension 调色板。
///
/// v6.1：category 8 色板混合主色族（4 档浅深）+ 环境色族（2 档）+ 互补色族（2 档），
/// 让分类调色板跨色域，匹配主页"主色 vs 环境色温互补"的视觉语言。
class ThemeAppColors {
  ThemeAppColors._();

  /// 墨青主题（light）— info 用陶橙（互补），category 跨蓝/暖灰/陶橙。
  static const AppColorsExtension light = AppColorsExtension(
    success: Color(0xFF84BD9C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDEEDE4),
    onSuccessContainer: Color(0xFF1F3F26),
    warning: Color(0xFFC2AD8E),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF0ECE5),
    onWarningContainer: Color(0xFF3F2D14),
    info: Color(0xFFBE9478),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFECDFD6),
    onInfoContainer: Color(0xFF4A2E1E),
    category: [
      Color(0xFFDAE3EC), Color(0xFF82A1BF), Color(0xFFBACBDC), Color(0xFF171D22),
      Color(0xFF9A907E), Color(0xFFBE9478), Color(0xFFECDFD6), Color(0xFF221B16),
    ],
  );

  /// 夜间主题（dark）— info 用暖橙（互补），category 跨深蓝/暖灰/暖橙。
  static const AppColorsExtension dark = AppColorsExtension(
    success: Color(0xFF95B89E),
    onSuccess: Color(0xFF0F1419),
    successContainer: Color(0xFF2A3F30),
    onSuccessContainer: Color(0xFFB8D6BE),
    warning: Color(0xFFD4B68E),
    onWarning: Color(0xFF0F1419),
    warningContainer: Color(0xFF4A3D24),
    onWarningContainer: Color(0xFFF0D9A8),
    info: Color(0xFFC49B7C),
    onInfo: Color(0xFF0F1419),
    infoContainer: Color(0xFF3A2E22),
    onInfoContainer: Color(0xFFF0D9A8),
    category: [
      Color(0xFFE1E6EC), Color(0xFF9AADC1), Color(0xFFC7D2DD), Color(0xFF1C1F23),
      Color(0xFFA8A094), Color(0xFFC49B7C), Color(0xFFEDE1D8), Color(0xFF231C16),
    ],
  );

  /// 茶玫主题（pink）— info 用青绿（互补），category 跨粉/青绿/青绿。
  static const AppColorsExtension pink = AppColorsExtension(
    success: Color(0xFF84BD9C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDEEDE4),
    onSuccessContainer: Color(0xFF1F3F26),
    warning: Color(0xFFC2AD8E),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF0ECE5),
    onWarningContainer: Color(0xFF3F2D14),
    info: Color(0xFF6FA58C),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFD4E4DC),
    onInfoContainer: Color(0xFF1F3A2A),
    category: [
      Color(0xFFF5E9EB), Color(0xFFDEB5BD), Color(0xFFEDD6DB), Color(0xFF282122),
      Color(0xFF7E9A8F), Color(0xFF6FA58C), Color(0xFFD4E4DC), Color(0xFF141E19),
    ],
  );

  /// 苔绿主题（green）— info 用玫紫（互补），category 跨绿/玫紫/玫紫。
  static const AppColorsExtension green = AppColorsExtension(
    success: Color(0xFF84BD9C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDEEDE4),
    onSuccessContainer: Color(0xFF1F3F26),
    warning: Color(0xFFC2AD8E),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF0ECE5),
    onWarningContainer: Color(0xFF3F2D14),
    info: Color(0xFFB58CA6),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFE9DCE4),
    onInfoContainer: Color(0xFF3E2A38),
    category: [
      Color(0xFFDCE8D6), Color(0xFF8AB276), Color(0xFFBFD5B4), Color(0xFF192015),
      Color(0xFF9A7E8F), Color(0xFFB58CA6), Color(0xFFE9DCE4), Color(0xFF21191E),
    ],
  );

  /// 陶橙主题（orange）— info 用雾蓝（互补），category 跨橙/蓝/蓝。
  static const AppColorsExtension orange = AppColorsExtension(
    success: Color(0xFF84BD9C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDEEDE4),
    onSuccessContainer: Color(0xFF1F3F26),
    warning: Color(0xFFC2AD8E),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF0ECE5),
    onWarningContainer: Color(0xFF3F2D14),
    info: Color(0xFF7C9BB8),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFD8E1EA),
    onInfoContainer: Color(0xFF23304A),
    category: [
      Color(0xFFF5EAE4), Color(0xFFDEB8A6), Color(0xFFEDD8CE), Color(0xFF28211E),
      Color(0xFF7E8B9A), Color(0xFF7C9BB8), Color(0xFFD8E1EA), Color(0xFF161C21),
    ],
  );

  /// 玫紫主题（rose）— info 用苔绿（互补），category 跨玫/苔绿/苔绿。
  static const AppColorsExtension rose = AppColorsExtension(
    success: Color(0xFF84BD9C),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDEEDE4),
    onSuccessContainer: Color(0xFF1F3F26),
    warning: Color(0xFFC2AD8E),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFF0ECE5),
    onWarningContainer: Color(0xFF3F2D14),
    info: Color(0xFF73996E),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFD5E0D4),
    onInfoContainer: Color(0xFF22381E),
    category: [
      Color(0xFFF4E6E9), Color(0xFFD9ABB6), Color(0xFFEAD1D7), Color(0xFF271F21),
      Color(0xFF839A7E), Color(0xFF73996E), Color(0xFFD5E0D4), Color(0xFF151C14),
    ],
  );

  /// 暮紫主题（purple）— info 用鎏金（互补），category 跨紫/金/金。
  static const AppColorsExtension purple = AppColorsExtension(
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