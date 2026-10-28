// Layer 4: BaseButton 原子组件。
//
// OutlinedButton 风格，色由 ColorStrategy 提供（onSurface fg + outline border）。
// 局部 fg/border/bg 颜色覆盖：通过临时策略包装实现（不破坏全局 strategy）。

import 'package:flutter/material.dart';

import '../../../../core/theme/extensions/color_strategy_extension.dart';
import '../../../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../../../core/theme/colors/strategy/color_strategy/themes/default.dart';
import '../../../../design_tokens/radius.dart';

class BaseButton extends StatelessWidget {
  const BaseButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.foreground,
    this.border,
    this.background,
    this.fullWidth = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? foreground;
  final Color? border;
  final Color? background;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final s = _resolve(context);
    final fg = foreground ?? s.text;
    final bd = border ?? s.outline;
    final bg = background;

    final style = OutlinedButton.styleFrom(
      foregroundColor: fg,
      side: BorderSide(color: bd),
      backgroundColor: bg,
      minimumSize: const Size(88, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
    );

    final button = icon != null
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label),
            style: style,
          )
        : OutlinedButton(
            style: style,
            onPressed: onPressed,
            child: Text(label),
          );

    return fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }

  ColorStrategy _resolve(BuildContext context) {
    final hasOverride =
        foreground != null || border != null || background != null;
    if (hasOverride) {
      // 局部覆盖：委托全局 strategy，fg/border/surface 三个角色被覆盖
      final ext = Theme.of(context).extension<ColorStrategyExtension>();
      final delegate = ext?.strategy ??
          DefaultColorStrategy.of(Theme.of(context).colorScheme);
      return _LocalOverrideStrategy(
        delegate: delegate,
        foreground: foreground,
        border: border,
        surfaceOverride: background,
      );
    }
    final ext = Theme.of(context).extension<ColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultColorStrategy.of(Theme.of(context).colorScheme);
  }
}

/// 局部 override 策略：保留全局 strategy，但 fg/border/surface 三个角色被覆盖
class _LocalOverrideStrategy implements ColorStrategy {
  _LocalOverrideStrategy({
    required this.delegate,
    this.foreground,
    this.border,
    this.surfaceOverride,
  });

  final ColorStrategy delegate;
  final Color? foreground;
  final Color? border;
  final Color? surfaceOverride;

  @override
  Color get accent => delegate.accent;
  @override
  Color get outline => border ?? delegate.outline;
  @override
  Color get text => foreground ?? delegate.text;
  @override
  Color get textMuted => delegate.textMuted;
  @override
  Color get danger => delegate.danger;
  @override
  Color get surface => surfaceOverride ?? delegate.surface;
  @override
  ColorScheme get scheme => delegate.scheme;
}
// ── BaseIconButton（原子件）──

// Layer 4: BaseIconButton 原子组件。
//
// 圆形 IconButton，3 种 variant：
//   - tint    : color@10% bg
//   - outline : surface bg + outline 边框
//   - hero    : accent bg + glow

enum BaseIconButtonVariant { tint, outline, hero }

class BaseIconButton extends StatelessWidget {
  const BaseIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.background,
    this.size = 44,
    this.iconSize = 24,
    this.variant = BaseIconButtonVariant.tint,
    this.strategy,
  });

  final IconData icon;
  final VoidCallback? onTap;

  /// 无障碍提示；非 null 时包一层 [Tooltip]。
  final String? tooltip;

  /// 主色覆盖（默认 null → 走 strategy.accent）
  final Color? color;

  /// 背景覆盖
  final Color? background;

  final double size;
  final double iconSize;
  final BaseIconButtonVariant variant;
  final ColorStrategy? strategy;

  @override
  Widget build(BuildContext context) {
    final s = _resolve(context);
    final base = color ?? s.accent;

    final (bg, fg) = switch (variant) {
      BaseIconButtonVariant.tint => (base.withValues(alpha: 0.1), base),
      BaseIconButtonVariant.outline => (s.surface, base),
      BaseIconButtonVariant.hero => (base, s.text),
    };

    final decoration = switch (variant) {
      BaseIconButtonVariant.outline => BoxDecoration(
          color: background ?? bg,
          shape: BoxShape.circle,
          border: Border.all(color: s.outline, width: 1),
        ),
      BaseIconButtonVariant.hero => BoxDecoration(
          color: base,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: base.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
      _ => BoxDecoration(
          color: background ?? bg,
          shape: BoxShape.circle,
        ),
    };

    final effectiveIconSize =
        variant == BaseIconButtonVariant.hero ? 48.0 : iconSize;

    final button = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: decoration,
        child: Icon(icon, color: fg, size: effectiveIconSize),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }

  ColorStrategy _resolve(BuildContext context) {
    final injected = strategy;
    if (injected != null) return injected;
    final ext = Theme.of(context).extension<ColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultColorStrategy.of(Theme.of(context).colorScheme);
  }
}
// ── EmphasisButton（边框强调样式包）──

/// 边框强调风格按钮（替代纯色色块）
///
/// 用户痛点：FilledButton/ElevatedButton 默认是主题色纯色实心块（"塑料感"）；
/// 改成边框强调后视觉更克制：浅色调底 + 彩色描边 + 彩色文字。
///
/// **完全从 [Theme.of(context).colorScheme] 取色**，不依赖任何硬编码调色板
/// —— 配合当前主题（light/dark/pink/green/orange/rose/purple）自动呈现对应色相。
///
/// 三档语义：
/// - [borderEmphasis] —— 一般功能（登录/发送/保存/确认 等）
/// - [dangerEmphasis]  —— 破坏性操作（删除/取消等）
/// - [ghostEmphasis]  —— 次要辅助（透底仅文字颜色）
///
/// 用法：
///   OutlinedButton(
///     style: EmphasisButton.borderEmphasis(context, color: colorScheme.primary),
///     onPressed: ...,
///     child: Text('发送'),
///   )
abstract final class EmphasisButton {
  /// 统一圆角：从主题 cardTheme 取，缺省 14
  static double _radiusOf(BuildContext context) {
    final shape = Theme.of(context).cardTheme.shape;
    if (shape is RoundedRectangleBorder) {
      final br = shape.borderRadius;
      if (br is BorderRadius) return br.topLeft.x;
    }
    return 14;
  }

  /// 边框强调按钮样式（一般功能）
  ///
  /// [color] 一般传 `colorScheme.primary`；破坏性场景可传自定义红/橙。
  static ButtonStyle borderEmphasis(
    BuildContext context, {
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final radius = _radiusOf(context);
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      backgroundColor: color.withValues(alpha: isDark ? 0.18 : 0.08),
      side: BorderSide(
        color: color.withValues(alpha: isDark ? 0.65 : 0.5),
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );
  }

  /// 边框强调按钮样式（破坏性）—— 红色由 [colorScheme.error] 派生
  static ButtonStyle dangerEmphasis(BuildContext context) {
    final danger = Theme.of(context).colorScheme.error;
    return borderEmphasis(context, color: danger);
  }

  /// 透明边框（次要辅助，仅文字颜色，无描边）
  static ButtonStyle ghostEmphasis(
    BuildContext context, {
    required Color color,
  }) {
    final radius = _radiusOf(context);
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    );
  }
}
