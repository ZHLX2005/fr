// Zen 家族主题（v6 Heritage 架构）。
//
// 仅保留纯样式 helper 与一个 Scaffold 便利函数；所有 widget class 已折叠
// 到 lib/widgets/base/*（见 commit 5），调用方改用 BaseSection/BaseIconButton/
// BaseDot/BaseEmptyState/BaseSwipeAction/BaseConfirmDialog。
//
// 保留：
//   - ZenText / zenCardTheme / zenButtonTheme：纯样式 helper（无 Widget 返回）
//   - zenPageScaffold：Scaffold 包装函数，无对应 Base*，作为唯一 Zen 域便利函数

import 'package:flutter/material.dart';

import '../../../core/styling/colors/strategy/color_strategy/themes/default.dart';
import '../../../core/styling/context/colors.dart';

// =====================================================================
// Zen 排版（保持 const 以兼容 const widget）
// =====================================================================

/// Zen 排版风格集合（const TextStyle）。
///
/// 注：color 字段为硬编码暖墨色 / 暖灰，是 zen 家族识别的一部分。
/// 若需要完全跟主题（夜/亮），调用方用 .copyWith(color: scheme.X) 覆盖。
class ZenText {
  ZenText._();

  static const body = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 16,
    height: 1.3,
  );

  static const label = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 13,
  );

  static const title = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 22,
    fontWeight: FontWeight.w600,
  );

  static const button = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const monoDigit = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 40,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const monoDigitLarge = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 64,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const monoDigitSmall = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 14,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Zen 卡片装饰（v6 Heritage：读 ColorStrategy）。
BoxDecoration zenCardTheme(BuildContext context) {
  final s = DefaultColorStrategy.of(Theme.of(context).colorScheme);
  return BoxDecoration(
    color: s.surface,
    border: Border.all(color: s.outline, width: 2),
    borderRadius: BorderRadius.circular(6),
  );
}

/// Zen 按钮样式（v6 Heritage）。
ButtonStyle zenButtonTheme(
  BuildContext context, {
  Color? foreground,
  Color? border,
}) {
  return OutlinedButton.styleFrom(
    foregroundColor: foreground ?? context.colors.text,
    side: BorderSide(color: border ?? context.colors.outline),
    minimumSize: const Size(88, 44),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    textStyle: ZenText.button,
  );
}

// =====================================================================
// Scaffold 便利函数（唯一保留的非纯样式 helper）
// =====================================================================

/// Zen 标准页面外壳。
Scaffold zenPageScaffold({
  required BuildContext context,
  required String title,
  required Widget body,
  List<Widget>? actions,
  Widget? fab,
  Widget? bottomNavigationBar,
  Color? backgroundColor,
  Widget? leading,
}) {
  final scheme = Theme.of(context).colorScheme;
  return Scaffold(
    backgroundColor: backgroundColor ?? scheme.surface,
    appBar: AppBar(
      backgroundColor: scheme.surface,
      elevation: 0,
      title: Text(title, style: ZenText.title),
      actions: actions,
      leading: leading,
    ),
    body: body,
    floatingActionButton: fab,
    bottomNavigationBar: bottomNavigationBar,
  );
}
