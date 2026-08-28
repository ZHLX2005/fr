// Layer 3 — Semantic typography.
//
// 应用 TextTheme 构建器（基于 M3 + AppFontFamily）。
// 字号档位与 AppSpacing 节奏保持视觉对齐。
//
// 设计意图：tokens 提供 font family 与 weight，
// semantic TextTheme 决定"什么场景用什么字 + 字号"。

import 'package:flutter/material.dart';
import 'tokens/typography.dart';

/// 应用 TextTheme 构建器。
///
/// 当前实现：默认沿用 M3 TextTheme（保持原 ZenText/裸用 Theme.of 行为兼容），
/// 仅替换 fontFamily + fontFamilyFallback 为 [AppFontFamily.sans] / [.sansFallback]。
/// 后续如需集中调字号/字重档位，在这里改。
class AppTextThemes {
  AppTextThemes._();

  static TextTheme build(Brightness brightness) {
    // 沿用 M3 默认字号档位，只换 fontFamily + fontFamilyFallback。
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;
    return _applyFont(base);
  }

  /// 把主字体 + 回退链统一应用到 M3 默认 TextTheme 的所有 15 档。
  static TextTheme _applyFont(TextTheme base) {
    final family = AppFontFamily.sans;
    final fallback = AppFontFamily.sansFallback;
    TextStyle? apply(TextStyle? s) =>
        s?.copyWith(fontFamily: family, fontFamilyFallback: fallback);
    return base.copyWith(
      displayLarge: apply(base.displayLarge),
      displayMedium: apply(base.displayMedium),
      displaySmall: apply(base.displaySmall),
      headlineLarge: apply(base.headlineLarge),
      headlineMedium: apply(base.headlineMedium),
      headlineSmall: apply(base.headlineSmall),
      titleLarge: apply(base.titleLarge),
      titleMedium: apply(base.titleMedium),
      titleSmall: apply(base.titleSmall),
      bodyLarge: apply(base.bodyLarge),
      bodyMedium: apply(base.bodyMedium),
      bodySmall: apply(base.bodySmall),
      labelLarge: apply(base.labelLarge),
      labelMedium: apply(base.labelMedium),
      labelSmall: apply(base.labelSmall),
    );
  }
}