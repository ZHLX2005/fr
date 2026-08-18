// Layer 1 — Raw typography tokens.
//
// font family 与 weight 是跨所有文本/数字组件的"骨架"，
// 不感知具体字号大小（字号由 semantic/typography.dart 的 TextTheme 决定）。
//
// 这里的设计意图：tokens 是字体本身的属性，
// semantic TextTheme 才是"什么场景用什么字"。

import 'package:flutter/material.dart';

/// 应用字体族。
///
/// - [sans]：西文与中文混排默认族（沿用 zen_theme 链路）。
/// - [mono]：数字 / 时钟 / 倒计时专用等宽族（tabularFigures）。
class AppFontFamily {
  AppFontFamily._();

  /// 无衬线族：系统字体回退链（macOS / Windows / Android / iOS）。
  static const sans =
      '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, '
      '"Helvetica Neue", Arial, sans-serif';

  /// 等宽族：用于数字、时钟、时间显示，配合 FontFeature.tabularFigures。
  static const mono = 'SF Mono, Menlo, Consolas, monospace';
}

/// 常用字重常量（仅语义命名，不引入新值）。
///
/// 用途：在 widget 内 `fontWeight: AppFontWeight.regular` 比直接写
/// `FontWeight.w400` 更可读，也方便未来统一调档。
class AppFontWeight {
  AppFontWeight._();

  static const thin = FontWeight.w200;
  static const light = FontWeight.w300;
  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500;
  static const semibold = FontWeight.w600;
  static const bold = FontWeight.w700;
}