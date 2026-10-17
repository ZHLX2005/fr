// Layer 1 — Raw radius tokens.
//
// 应用全局圆角节奏：4 / 6 / 8 / 12 / 16 / 24。
// 卡片、按钮、Tag、Sheet 等容器圆角优先从这里取。

import 'package:flutter/material.dart';

/// 应用圆角 token。
///
/// 命名按"语义档位"：
///   - xs (4)  ：Tag / 小型按钮
///   - sm (6)  ：zen 卡片（沿用旧 zen_radius 风格）
///   - md (8)  ：输入框 / 列表项
///   - lg (12) ：按钮
///   - xl (16) ：卡片（Material 3 标准）
///   - xxl(24) ：Hero 大卡 / 顶部 hero 区
class AppRadius {
  AppRadius._();

  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double xxl = 24;
}

/// 常用 BorderRadius（节省 widget 端重复构造）。
class AppBorderRadius {
  AppBorderRadius._();

  static final BorderRadius allXs = BorderRadius.circular(AppRadius.xs);
  static final BorderRadius allSm = BorderRadius.circular(AppRadius.sm);
  static final BorderRadius allMd = BorderRadius.circular(AppRadius.md);
  static final BorderRadius allLg = BorderRadius.circular(AppRadius.lg);
  static final BorderRadius allXl = BorderRadius.circular(AppRadius.xl);
  static final BorderRadius allXxl = BorderRadius.circular(AppRadius.xxl);
}