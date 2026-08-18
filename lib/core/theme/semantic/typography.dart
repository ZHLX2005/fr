// Layer 2 — Semantic typography.
//
// 应用 TextTheme 构建器（基于 M3 + AppFontFamily）。
// 字号档位见 ../tokens/spacing.dart 节奏，保持视觉对齐。
//
// 设计意图：tokens 提供 font family 与 weight，
// semantic TextTheme 决定"什么场景用什么字 + 字号"。

import 'package:flutter/material.dart';
import '../tokens/typography.dart';

/// 应用 TextTheme 构建器。
///
/// 当前实现：默认沿用 M3 TextTheme（保持原 ZenText/裸用 Theme.of 行为兼容），
/// 仅替换 fontFamily 为 [AppFontFamily.sans]。
/// 后续如需集中调字号/字重档位，在这里改。
class AppTextThemes {
  AppTextThemes._();

  static TextTheme build(Brightness brightness) {
    // 沿用 M3 默认字号档位，只换 fontFamily。
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    return base.copyWith(
      // body / display / headline / title / label 全部继承 fontFamily
      displayLarge: base.displayLarge?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontFamily: AppFontFamily.sans,
      ),
    );
  }
}