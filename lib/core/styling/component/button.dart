// Layer 3 — Component theme: Button.
//
// 应用 Button 主题。Flutter 内置 ElevatedButtonTheme/FilledButtonTheme/
// TextButtonTheme/OutlinedButtonTheme 已在 ThemeData 中注册，
// 这里只补充"非内置"的复合按钮样式（如 hero 圆形按钮）。
//
// 未来如需集中管理按钮风格（圆角、内边距、状态层透明度），
// 优先扩展 Flutter 内置 componentThemes；本文件留作自定义按钮入口。

import 'package:flutter/material.dart';

/// 应用按钮主题工具。
class AppButtonThemes {
  AppButtonThemes._();

  /// 通用主按钮样式（读自 ColorScheme，无硬编码颜色）。
  static ButtonStyle primary(BuildContext context) =>
      ElevatedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );

  /// 通用次按钮样式。
  static ButtonStyle secondary(BuildContext context) =>
      OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      );
}