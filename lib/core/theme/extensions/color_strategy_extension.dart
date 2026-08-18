// Layer 3: ThemeExtension 注入器。
//
// 关键设计：
// 1. 只存 strategy 实例（不存 BuildContext，避免内存泄露）
// 2. lerp 返回 this 或 other（强制 widget 重建，触发布局更新）
// 3. 不做颜色插值：策略切换是离散事件（不是渐变），跨色 lerp 会产生鬼影

import 'package:flutter/material.dart';

import '../strategy/color_strategy.dart';

class ColorStrategyExtension extends ThemeExtension<ColorStrategyExtension> {
  final ColorStrategy strategy;

  const ColorStrategyExtension(this.strategy);

  @override
  ColorStrategyExtension copyWith({ColorStrategy? strategy}) {
    return ColorStrategyExtension(strategy ?? this.strategy);
  }

  // ★ lerp 必须返回 this 或 other，不能 return this 写死
  // 也不能 Color.lerp() 插值（策略是离散事件，不是渐变值）
  @override
  ColorStrategyExtension lerp(
    ThemeExtension<ColorStrategyExtension>? other,
    double t,
  ) {
    if (other is! ColorStrategyExtension) return this;
    // 50% 阈值切换，避免插值产生中间状态
    return t < 0.5 ? this : other;
  }
}