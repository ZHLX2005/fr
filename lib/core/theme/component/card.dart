// Layer 3 — Component theme: Card.
//
// 应用 Card 主题。Flutter 内置 CardThemeData 已注册在 ThemeData 中，
// 这里只补充"非内置"的卡片装饰（带阴影、强调色背景等）。
//
// 业务页用到 Card 时，优先用 Material 自带 Card；需要自定义时，
// 用本文件的 AppCardDecorations。

import 'package:flutter/material.dart';

/// 应用卡片装饰工具。
class AppCardDecorations {
  AppCardDecorations._();

  /// 浅色阴影卡片（surface + hair 边框）。
  static BoxDecoration flat(BuildContext context) => BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(16),
      );

  /// 强调色卡片（accent 背景 + onAccent 文字）。
  static BoxDecoration accent(BuildContext context) => BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.25),
            offset: const Offset(0, 8),
            blurRadius: 24,
          ),
        ],
      );
}