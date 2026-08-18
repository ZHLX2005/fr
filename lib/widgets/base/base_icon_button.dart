// Layer 4: BaseIconButton 原子组件。
//
// 圆形 IconButton，3 种 variant：
//   - tint    : color@10% bg
//   - outline : surface bg + outline 边框
//   - hero    : accent bg + glow

import 'package:flutter/material.dart';

import '../../core/theme/extensions/color_strategy_extension.dart';
import '../../core/theme/strategy/color_strategy.dart';
import '../../core/theme/strategy/default_color_strategy.dart';

enum BaseIconButtonVariant { tint, outline, hero }

class BaseIconButton extends StatelessWidget {
  const BaseIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.background,
    this.size = 44,
    this.iconSize = 24,
    this.variant = BaseIconButtonVariant.tint,
    this.strategy,
  });

  final IconData icon;
  final VoidCallback? onTap;

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

    return InkWell(
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
  }

  ColorStrategy _resolve(BuildContext context) {
    final injected = strategy;
    if (injected != null) return injected;
    final ext = Theme.of(context).extension<ColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultColorStrategy.of(Theme.of(context).colorScheme);
  }
}