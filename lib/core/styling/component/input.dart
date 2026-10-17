// Layer 3 — Component theme: Input.
//
// 应用 Input 主题。Flutter 内置 InputDecorationTheme 已在 ThemeData 中注册，
// 这里只补充"非内置"的输入组件。

import 'package:flutter/material.dart';

/// 应用输入框主题工具。
class AppInputThemes {
  AppInputThemes._();

  /// 标准 InputDecoration（读自 ColorScheme，无硬编码颜色）。
  static InputDecoration standard(
    BuildContext context, {
    required String label,
    String? hint,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 2,
          ),
        ),
      );
}