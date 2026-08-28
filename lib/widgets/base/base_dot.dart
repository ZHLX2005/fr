// Layer 4: BaseDot 原子组件。
//
// 三层兜底：
//   1. 局部 strategy 注入（最高优先级）
//   2. Theme.of(context).extension<ColorStrategyExtension>() 注入
//   3. 直接用 ColorScheme 构造 DefaultColorStrategy（终极兜底）
//
// 零强制解包（`!`），绝不崩溃。

import 'package:flutter/material.dart';

import '../../core/theme/extensions/color_strategy_extension.dart';
import '../../core/theme/colors/strategy/color_strategy/color_strategy.dart';
import '../../core/theme/colors/strategy/color_strategy/themes/default.dart';

/// 12×12 状态点。
class BaseDot extends StatelessWidget {
  const BaseDot({
    super.key,
    required this.active,
    this.size = 12,
    this.strategy,
  });

  final bool active;
  final double size;

  /// 局部策略注入（默认 null → 走全局 ThemeExtension）。
  final ColorStrategy? strategy;

  @override
  Widget build(BuildContext context) {
    final s = _resolveStrategy(context);
    final color = s.accent;
    final border = s.textMuted;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: active ? color : Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
        border: Border.all(color: active ? color : border),
        shape: BoxShape.circle,
      ),
    );
  }

  /// 三层兜底解析策略：注入 > Extension > DefaultColorStrategy
  ColorStrategy _resolveStrategy(BuildContext context) {
    final injected = strategy;
    if (injected != null) return injected;
    final ext = Theme.of(context).extension<ColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultColorStrategy.of(Theme.of(context).colorScheme);
  }
}