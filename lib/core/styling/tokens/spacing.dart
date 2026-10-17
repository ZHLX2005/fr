// Layer 1 — Raw spacing tokens.
//
// 应用全局间距节奏：4 / 8 / 12 / 16 / 24 / 32 / 48。
// 所有 widget 的 padding / margin / SizedBox 间距优先从这里取，
// 禁止 widget 内出现 `padding: EdgeInsets.all(13)` 这类"野值"。

import 'package:flutter/material.dart';

/// 应用间距 token（4dp 节奏）。
///
/// 命名按"语义档位"而非数值：
///   - xxs (4)  ：紧凑连接（icon 与文字间隙）
///   - xs  (8)  ：组件内部紧凑间距
///   - sm  (12) ：列表项内边距
///   - md  (16) ：卡片内边距基线
///   - lg  (24) ：页面内边距 / 大块间距
///   - xl  (32) ：段落间距
///   - xxl (48) ：顶部留白
class AppSpacing {
  AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// 常用 EdgeInsets（节省 widget 端重复构造）。
class AppInsets {
  AppInsets._();

  static const EdgeInsets allMd = EdgeInsets.all(AppSpacing.md);
  static const EdgeInsets allLg = EdgeInsets.all(AppSpacing.lg);
  static const EdgeInsets pageHorizontal =
      EdgeInsets.symmetric(horizontal: AppSpacing.lg);

  /// 垂直 16（卡片内常用）。
  static const EdgeInsets cardVertical =
      EdgeInsets.symmetric(vertical: AppSpacing.md);
}