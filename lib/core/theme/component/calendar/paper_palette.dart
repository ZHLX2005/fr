// 日历 paper UI 主题入口 —— 从当前 ColorScheme 派生。
//
// 历史：v6.1 主题架构前 calendar/paper UI 直接读一组 const Color；
// v6.1 落地后曾保留 const shim（颜色取 zen）做兼容。现在按预留方案改为
// `PaperPalette.of(context)` 从 Theme.of(context).colorScheme 派生 ——
// 切换主题（茶禅/暮紫/墨白）时日历跟随主题。
//
// 字段语义映射（保留 paper 语汇）：
//   ink / inkMuted / inkFaint  → onSurface / onSurfaceVariant / 弱化档
//   line                       → outline
//   bg                         → surface（页/容器底色）
//   bgElevated                 → surfaceContainerHighest（深底）
//                                用于：AlertDialog/OutlinedButton 大按钮/
//                                "边框强调"纯展示卡/段选择器轨道/小 chip 选中态
//                                等不属"输入/表单选择"交互场景
//   bgCard                     → Color.lerp(surface, primaryContainer, 0.2)
//                                §0.1 契约浅色 —— 用于：输入框（TextField.fillColor）/
//                                表单选择控件选中态（chip_choice/pill_segmented）/
//                                底部表单 sheet 顶部容器 等"输入/选择"大色块
//   accent / today             → primary
//   highlight                  → tertiary

import 'package:flutter/material.dart';

class PaperPalette {
  const PaperPalette({
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.bg,
    required this.bgElevated,
    required this.bgCard,
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
      // 原"抬升底色"语义：surfaceContainerHighest，多数主题偏深。
      // 仅用于：AlertDialog/大按钮/纯展示卡/段选择器轨道/小 chip 选中态
      // （详见文件头字段映射表注释）。
      bgElevated: scheme.surfaceContainerHighest,
      // §0.1 契约浅色：80% surface + 20% primaryContainer。
      // 仅用于：输入框 / 表单选择控件选中态 / 表单 sheet 大色块容器。
      bgCard: Color.lerp(scheme.surface, scheme.primaryContainer, 0.2)!,
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
  /// 适用于：AlertDialog/大按钮/纯展示卡片/段选择器轨道/小 chip 选中态。
  final Color bgElevated;

  /// §0.1 大色块交互卡片浅色
  /// （`Color.lerp(surface, primaryContainer, 0.2)`）。
  /// 适用于：输入框（TextField.fillColor）/ 表单选择控件选中态
  /// （chip_choice/pill_segmented）/ 底部表单 sheet 大色块容器。
  final Color bgCard;

  /// 强调色（primary）。
  final Color accent;

  /// 高亮色（tertiary）。
  final Color highlight;

  /// 今日高亮（与 accent 同色，强调"今日"语义）。
  final Color today;
}
