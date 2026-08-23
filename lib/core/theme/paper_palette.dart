// 旧主题系统的兼容 shim —— 历史 const Color API。
//
// 由来：v6.1 主题架构把所有颜色统一成 ColorScheme 派生（参考 semantic/colors.dart
// 与 strategy/*）。这之前 calendar / paper UI 直接读 PaperPalette 一组 const Color
// (ink / line / accent / bg / …)，迁移新主题后没有重新派生 ColorScheme 引用。
//
// 处理：因为这些调用都是 const 上下文（const BorderSide / TextStyle），最稳妥的
// 兼容做法是保留 PaperPalette 类与 const 颜色字段。颜色取自 zen 主题（暖米纸面 +
// sage 强调），与 calendar UI 视觉气质匹配；后续真要做主题联动再换为
// PaperPalette.of(context) 派生方案。
//
// 不再用于产品代码；新建页面请用 Theme.of(context).colorScheme。

import 'package:flutter/material.dart';

class PaperPalette {
  PaperPalette._();

  /// 主文字色（深墨）。
  static const Color ink = Color(0xFF252118);

  /// 次级文字（环境灰文字）。
  static const Color inkMuted = Color(0xFF706A5C);

  /// 弱化文字（环境弱字）。
  static const Color inkFaint = Color(0xFFB5A88A);

  /// 边线色（outline 同系）。
  static const Color line = Color(0xFFDCD8D0);

  /// 纸面底色（surface）。
  static const Color bg = Color(0xFFFAF9F7);

  /// 抬高底色（surfaceContainerHighest，比 surface 略深）。
  static const Color bgElevated = Color(0xFFF3F2EE);

  /// 强调色（primary，sage 家族）。
  static const Color accent = Color(0xFF7A9A7E);

  /// 高亮色（tertiary / error 同系）。
  static const Color highlight = Color(0xFFA0594A);

  /// 今日高亮（与 accent 同色，强调"今日"语义）。
  static const Color today = Color(0xFF7A9A7E);
}
