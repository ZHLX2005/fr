// Layer 3: TetrisColorStrategy ThemeExtension 注入器。
//
// lerp 50% 阈值切换（策略是离散事件，不插值渐变）。

import 'package:flutter/material.dart';

import '../colors/strategy/tetris_color_strategy/tetris_color_strategy.dart';

class TetrisColorStrategyExtension extends ThemeExtension<TetrisColorStrategyExtension> {
  final TetrisColorStrategy strategy;

  const TetrisColorStrategyExtension(this.strategy);

  @override
  TetrisColorStrategyExtension copyWith({TetrisColorStrategy? strategy}) {
    return TetrisColorStrategyExtension(strategy ?? this.strategy);
  }

  @override
  TetrisColorStrategyExtension lerp(
    ThemeExtension<TetrisColorStrategyExtension>? other,
    double t,
  ) {
    if (other is! TetrisColorStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}