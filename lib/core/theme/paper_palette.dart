// 日历 paper UI 主题入口 —— 从当前 ColorScheme 派生。
//
// 历史：v6.1 主题架构前 calendar/paper UI 直接读一组 const Color；
// v6.1 落地后曾保留 const shim（颜色取 zen）做兼容。现在按预留方案改为
// `PaperPalette.of(context)` 从 Theme.of(context).colorScheme 派生 ——
// 切换主题（茶禅/暮紫/墨白）时日历跟随主题。
//
// 字段语义映射（保留 paper 语汇）：
//   ink / inkMuted / inkFaint → onSurface / onSurfaceVariant / 弱化档
//   line                      → outline
//   bg / bgElevated           → surface / surfaceContainerHighest
//   accent / today            → primary
//   highlight                 → tertiary

import 'package:flutter/material.dart';

class PaperPalette {
  const PaperPalette({
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.bg,
    required this.bgElevated,
    required this.accent,
    required this.highlight,
    required this.today,
  });

  /// 从当前主题派生（唯一入口）。
  static PaperPalette of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PaperPalette(
      ink: scheme.onSurface,
      inkMuted: scheme.onSurfaceVariant,
      inkFaint: scheme.onSurfaceVariant.withValues(alpha: 0.45),
      line: scheme.outline,
      bg: scheme.surface,
      bgElevated: scheme.surfaceContainerHighest,
      accent: scheme.primary,
      highlight: scheme.tertiary,
      today: scheme.primary,
    );
  }

  /// 主文字色（深墨）。
  final Color ink;

  /// 次级文字（环境灰文字）。
  final Color inkMuted;

  /// 弱化文字（环境弱字）。
  final Color inkFaint;

  /// 边线色（outline 同系）。
  final Color line;

  /// 纸面底色（surface）。
  final Color bg;

  /// 抬高底色（surfaceContainerHighest，比 surface 略深）。
  final Color bgElevated;

  /// 强调色（primary）。
  final Color accent;

  /// 高亮色（tertiary）。
  final Color highlight;

  /// 今日高亮（与 accent 同色，强调"今日"语义）。
  final Color today;
}
