// Layer 4: BaseCard 原子组件。
//
// 通用卡片容器：surface bg + outline 2px 边框 + 圆角 16。
// 边框规则（v6）：所有边框统一 outline 2px，不撞主色。

import 'package:flutter/material.dart';

import '../../core/theme/extensions/color_strategy_extension.dart';
import '../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../core/theme/colors/strategy/color_strategy/themes/default.dart';

class BaseCard extends StatelessWidget {
  const BaseCard({
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
    this.strategy,
    this.child,
  });

  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final ColorStrategy? strategy;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final s = _resolve(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: s.surface,
        border: Border.all(color: s.outline, width: 2),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
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