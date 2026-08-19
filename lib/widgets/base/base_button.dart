// Layer 4: BaseButton 原子组件。
//
// OutlinedButton 风格，色由 ColorStrategy 提供（onSurface fg + outline border）。
// 局部 fg/border/bg 颜色覆盖：通过临时策略包装实现（不破坏全局 strategy）。

import 'package:flutter/material.dart';

import '../../core/theme/extensions/color_strategy_extension.dart';
import '../../core/theme/strategy/color_strategy.dart';
import '../../core/theme/strategy/default_color_strategy.dart';

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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