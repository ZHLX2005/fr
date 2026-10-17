// Layer 1 — Raw elevation tokens.
//
// 应用全局阴影节奏：sm / md / lg。
// 用于卡片、Hero 区、Modal 等抬升容器。

import 'package:flutter/material.dart';

/// 应用阴影 token。
///
/// - [sm]：浅阴影，卡片默认。
/// - [md]：中等阴影，悬浮卡片 / Sheet。
/// - [lg]：深阴影，Hero 大卡 / 弹窗。
class AppElevation {
  AppElevation._();

  /// 浅阴影：4dp 抬升，12px blur。
  static List<BoxShadow> get sm => const [
    BoxShadow(
      color: Color(0x14000000),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];

  /// 中等阴影：8dp 抬升，24px blur。
  static List<BoxShadow> get md => const [
    BoxShadow(
      color: Color(0x14000000),
      offset: Offset(0, 8),
      blurRadius: 24,
    ),
  ];

  /// 深阴影：12dp 抬升，40px blur（alpha 加重）。
  static List<BoxShadow> get lg => const [
    BoxShadow(
      color: Color(0x29000000),
      offset: Offset(0, 12),
      blurRadius: 40,
    ),
  ];
}