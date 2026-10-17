// Layer 3 — Component theme: Section.
//
// "Section" 是带标题的小容器（在 zenTheme 中叫 ZenSection，
// 在 lab 中也可能用）。这里定义通用 Section 行为，
// 家族（zen/lab）再叠各自的特色。

import 'package:flutter/material.dart';

/// 通用 Section 风格。
///
/// 提供 padding、gap、border 等骨架，家族 widget 引用它并
/// 注入家族特有的标题样式 / 容器装饰。
class SectionTokens {
  SectionTokens._();

  /// 默认内边距：12（zen 默认）/ 16（lab 默认）。
  static const EdgeInsets defaultPadding = EdgeInsets.all(12);
  static const EdgeInsets widePadding = EdgeInsets.all(16);

  /// 默认标题与内容间距：8。
  static const double defaultGap = 8;

  /// 标题字号（M3 titleSmall）。
  static TextStyle? titleStyleOf(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          );
}