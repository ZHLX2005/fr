// Zen 家族主题（v6 Heritage 架构）。
//
// 角色：
//   - Zen 家族组件的"zen 风格"色：永远固定的 3 色（sage/hair/mutedRed）
//   - 通过 DefaultColorStrategy 注入，全 app 切 zen 主题时全树统一
//   - 切到其他主题时，zen 组件仍保留家族识别（不像 7 主题那样跟主题切）
//
// 设计：
//   - ZenText 保持 const（兼容 const widget）
//   - 其他 widget class 委托 Base* + DefaultColorStrategy.of(scheme)

import 'package:flutter/material.dart';
import '../context_colors.dart';

import '../base/base_dialog.dart';
import '../base/base_dot.dart';
import '../base/base_empty_state.dart';
import '../base/base_icon_button.dart';
import '../base/base_swipe_action.dart';
import '../../core/theme/strategy/default_color_strategy.dart';

// =====================================================================
// Zen 排版（保持 const 以兼容 const widget）
// =====================================================================

/// ⚠️ DEPRECATED：保留 ZenColors 类作为兼容层，让 23 个旧 consumer 文件继续编译。
/// 后续阶段会逐个迁移到 `Theme.of(context).colorScheme`。
/// 新代码请直接用 `DefaultColorStrategy.of(scheme)` 或 `ColorScheme.X`。
@Deprecated('Use ColorScheme or DefaultColorStrategy instead')
class ZenColors {
  ZenColors._();
  static const bg = Color(0xFFF4F1EA);
  static const ink = Color(0xFF2C2C2C);
  static const hair = Color(0xFFD9D5C8);
  static const secondary = Color(0xFF8A8475);
  static const sage = Color(0xFF7A9A7E);
  static const mutedRed = Color(0xFFA0594A);
  static const surface = Color(0xFFFBF8F1);
}

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
    color: Color(0xFF2C2C2C), // ZenColors.ink 内联
    height: 1.3,
  );

  static const label = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 13,
    color: Color(0xFF8A8475), // ZenColors.secondary 内联
  );

  static const title = TextStyle(
    fontFamily:
        '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: Color(0xFF2C2C2C),
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
    color: Color(0xFF2C2C2C),
  );

  static const monoDigitLarge = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 64,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Color(0xFF2C2C2C),
  );

  static const monoDigitSmall = TextStyle(
    fontFamily: 'SF Mono, Menlo, Consolas, monospace',
    fontSize: 14,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Color(0xFF8A8475),
  );
}

/// ⚠️ DEPRECATED：迁移期保留。改用 `BaseIconButtonVariant`。
@Deprecated('Use BaseIconButtonVariant from widgets/base/')
enum ZenIconButtonVariant { tint, outline, hero }

// =====================================================================
// Zen 风格 helper
// =====================================================================

/// Zen 卡片装饰（surface bg + outline 2px 边框 + 圆角 6）。
///
/// ⚠️ DEPRECATED 兼容版：读 ZenColors（Zen 家族固定色）。
/// 新代码用 [zenCardTheme]。
BoxDecoration zenCard({Color? color}) => BoxDecoration(
      color: color ?? ZenColors.surface,
      border: Border.all(color: ZenColors.hair, width: 1),
      borderRadius: BorderRadius.circular(6),
    );

/// Zen 卡片装饰（v6 Heritage：读 ColorStrategy）。
BoxDecoration zenCardTheme(BuildContext context) {
  final s = DefaultColorStrategy.of(Theme.of(context).colorScheme);
  return BoxDecoration(
    color: s.surface,
    border: Border.all(color: s.outline, width: 2),
    borderRadius: BorderRadius.circular(6),
  );
}

/// Zen 点状区域（surface bg + outline 边框 solid）。
///
/// ⚠️ DEPRECATED 兼容版。
BoxDecoration zenDottedZone() => BoxDecoration(
      color: ZenColors.surface,
      border: Border.all(color: ZenColors.hair, width: 1, style: BorderStyle.solid),
      borderRadius: BorderRadius.circular(6),
    );

/// Zen 点状区域（v6 Heritage）。
BoxDecoration zenDottedZoneTheme(BuildContext context) {
  final s = DefaultColorStrategy.of(Theme.of(context).colorScheme);
  return BoxDecoration(
    color: s.surface,
    border: Border.all(
      color: s.outline,
      width: 1,
      style: BorderStyle.solid,
    ),
    borderRadius: BorderRadius.circular(6),
  );
}

/// Zen 按钮样式（onSurface fg + outline border + ZenText.button 字号）。
///
/// ⚠️ DEPRECATED 兼容版。
ButtonStyle zenButton({Color? foreground, Color? border, Color? background}) =>
    OutlinedButton.styleFrom(
      foregroundColor: foreground ?? ZenColors.ink,
      side: BorderSide(color: border ?? ZenColors.hair),
      backgroundColor: background,
      minimumSize: const Size(88, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      textStyle: ZenText.button,
    );

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
// Zen 家族 widget class（委托 Base* + 锁定 DefaultColorStrategy）
// =====================================================================

/// Section card with a small label header.
///
/// 委托 BaseSection，注入 DefaultColorStrategy.of(scheme)。
class ZenSection extends StatelessWidget {
  const ZenSection({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.gap = 8,
  });

  final String title;
  final Widget child;
  final EdgeInsets padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final s = DefaultColorStrategy.of(Theme.of(context).colorScheme);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: s.surface,
        border: Border.all(color: s.outline, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: ZenText.label),
          SizedBox(height: gap),
          child,
        ],
      ),
    );
  }
}

/// Zen 圆形 IconButton（3 variant），委托 BaseIconButton + 锁定 DefaultColorStrategy。
class ZenIconButton extends StatelessWidget {
  const ZenIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.background,
    this.size = 44,
    this.iconSize = 24,
    this.variant = BaseIconButtonVariant.tint,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final Color? background;
  final double size;
  final double iconSize;
  final BaseIconButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    return BaseIconButton(
      icon: icon,
      onTap: onTap,
      color: color,
      background: background,
      size: size,
      iconSize: iconSize,
      variant: variant,
    );
  }
}

/// Zen 状态点（委托 BaseDot + 锁定 DefaultColorStrategy）。
class ZenDot extends StatelessWidget {
  const ZenDot({
    super.key,
    this.active = false,
    this.color,
    this.inactiveBorder,
    this.size = 12,
  });

  final bool active;
  final Color? color;
  final Color? inactiveBorder;
  final double size;

  @override
  Widget build(BuildContext context) {
    return BaseDot(
      active: active,
      size: size,
    );
  }
}

/// Zen 空状态（委托 BaseEmptyState + 锁定 DefaultColorStrategy）。
class ZenEmptyState extends StatelessWidget {
  const ZenEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.actionColor,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? actionColor;

  @override
  Widget build(BuildContext context) {
    return BaseEmptyState(
      icon: icon,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      actionColor: actionColor,
    );
  }
}

/// Zen 滑动操作按钮（委托 BaseSwipeAction，color 由调用方提供）。
class ZenSwipeAction extends StatelessWidget {
  const ZenSwipeAction({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.leftRounded = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool leftRounded;

  @override
  Widget build(BuildContext context) {
    return BaseSwipeAction(
      label: label,
      icon: icon,
      color: color,
      onTap: onTap,
      leftRounded: leftRounded,
    );
  }
}

/// Zen 确认弹窗（委托 BaseConfirmDialog，但传入 DefaultColorStrategy 锁 danger 色）。
class ZenConfirmDialog {
  const ZenConfirmDialog._();

  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String message,
    required VoidCallback onConfirm,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    Color? confirmColor,
  }) async {
    return BaseConfirmDialog.show(
      context: context,
      title: title,
      message: message,
      onConfirm: onConfirm,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      confirmColor: confirmColor,
    );
  }
}

// =====================================================================
// Formatters
// =====================================================================

String formatDuration(int seconds) {
  if (seconds <= 0) return '0s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  if (h > 0) return '${h}h ${m}m ${s}s';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}

String formatTime(int seconds) {
  final isNegative = seconds < 0;
  final absSeconds = seconds.abs();
  final h = absSeconds ~/ 3600;
  final m = (absSeconds % 3600) ~/ 60;
  final s = absSeconds % 60;
  final sign = isNegative ? '-' : '';
  if (h > 0) {
    return '$sign${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
  return '$sign${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

String formatRecordDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

// =====================================================================
// Backward compat: zenPageScaffold（保留，因为有 23 个 consumer 调用）
// =====================================================================

/// Zen 标准页面外壳（保留旧 API 兼容 consumer）。
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
    backgroundColor: backgroundColor ?? scheme.surfaceContainerHighest,
    appBar: AppBar(
      backgroundColor: scheme.surfaceContainerHighest,
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