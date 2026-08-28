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
/// - [sans]：主字体（CSS 通用族名）+ [sansFallback] 回退链（OS 系统字体）
/// - [mono]：等宽族，配合 [AppFontWeight] 的 tabularFigures 用于数字/时钟
///
/// Flutter 的 `fontFamily` 只接受单个 family name；OS 回退链走 `fontFamilyFallback`。
class AppFontFamily {
  AppFontFamily._();

  /// 主字体族：CSS 通用 sans-serif（Flutter 系统会按平台查找默认无衬线字体）。
  static const String sans = 'sans-serif';

  /// 系统字体回退链（macOS / Windows / Android / iOS 各自的默认无衬线）。
  /// 通过 `fontFamilyFallback` 传给 TextStyle，确保跨平台都有合理字体。
  static const List<String> sansFallback = [
    '-apple-system',
    'BlinkMacSystemFont',
    'Segoe UI',
    'Roboto',
    'Helvetica Neue',
    'Arial',
  ];

  /// 等宽族：用于数字、时钟、时间显示，配合 FontFeature.tabularFigures。
  static const String mono = 'monospace';

  /// 等宽族回退链。
  static const List<String> monoFallback = [
    'SF Mono',
    'Menlo',
    'Consolas',
  ];
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