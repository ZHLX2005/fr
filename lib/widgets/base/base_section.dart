// Layer 4: BaseSection 原子组件。
//
// 通用 Section 容器：标题 + 内容，surface bg + outline 边框 + 圆角 6。
// 默认 12px padding + 8px gap。

import 'package:flutter/material.dart';

import '../../core/theme/extensions/color_strategy_extension.dart';
import '../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../core/theme/colors/strategy/color_strategy/themes/default.dart';

class BaseSection extends StatelessWidget {
  const BaseSection({
    super.key,
    required this.title,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.gap = 8,
    this.strategy,
  });

  final String title;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double gap;
  final ColorStrategy? strategy;

  @override
  Widget build(BuildContext context) {
    final s = _resolve(context);
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
          Text(title, style: TextStyle(color: s.textMuted, fontSize: 13)),
          SizedBox(height: gap),
          child,
        ],
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