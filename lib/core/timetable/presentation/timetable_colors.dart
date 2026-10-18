import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart' show AppColorsExtension;

/// 课表配色通道。
///
/// 历史：原为 static const 字段（M1 时期），批量重构时被改为函数 + BuildContext 入参。
/// 调用方全部走 `TimetableColors.Xxx(context)`，跟随当前主题切换。
class TimetableColors {
  TimetableColors._();

  // ─── 课程色板（8 色）───
  // 主题豁免：原"莫兰迪 8 色"是设计语言身份（课表视觉风格），保留为 light 主题专用；
  //         非 light 主题走 AppColorsExtension.category 自适应。
  /// 莫兰迪 8 色：light 主题下专属课程底色（保留设计语言身份）。
  static const List<Color> _morandi = [
    Color(0xFF8B9DC3), // 灰蓝
    Color(0xFF9E8FA8), // 灰紫
    Color(0xFFB58AA5), // 灰粉
    Color(0xFFC49A8B), // 灰橘
    Color(0xFFA8C4A2), // 灰绿
    Color(0xFF7FAAAA), // 灰青
    Color(0xFFA5B5C4), // 雾蓝
    Color(0xFFC4B5A0), // 灰棕
  ];

  /// 获取课程色：light 主题用莫兰迪，dark/pink/... 走 AppColorsExtension.category。
  static Color getCourseColor(BuildContext context, int seed) {
    final scheme = Theme.of(context);
    final isLight = scheme.brightness == Brightness.light;
    if (isLight) return _morandi[seed % _morandi.length];
    final cat = scheme.extension<AppColorsExtension>()?.category ?? _morandi;
    return cat[seed % cat.length];
  }

  // ─── 边框强调（中性灰 → 走 scheme.outline） ───
  static Color accent(BuildContext context) =>
      Theme.of(context).colorScheme.outline;
  static Color accentLight(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  // ─── 鼠尾草绿：zen 家族识别色（主题豁免） ───
  static const Color sage = Color(0xFF7A9A7E);

  // ─── 选中 / 边框 / 文字 / 表面（走 scheme 派生） ───
  static Color selectedBg(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  static Color border(BuildContext context) =>
      Theme.of(context).colorScheme.outline;
  static Color borderLight(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface;
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;
  static Color textTertiary(BuildContext context) =>
      Theme.of(context).colorScheme.outline;
  static Color surface(BuildContext context) =>
      Theme.of(context).colorScheme.surface;
  static Color surfaceVariant(BuildContext context) =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
}