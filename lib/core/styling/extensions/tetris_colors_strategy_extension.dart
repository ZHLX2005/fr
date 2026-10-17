// Layer 3: TetrisColorsStrategy ThemeExtension 注入器。
//
// lerp 50% 阈值切换（策略是离散事件，不插值渐变）。

import 'package:flutter/material.dart';

import '../colors/strategy/tetris_colors_strategy/tetris_colors_strategy.dart';

class TetrisColorsStrategyExtension extends ThemeExtension<TetrisColorsStrategyExtension> {
  final TetrisColorsStrategy strategy;

  const TetrisColorsStrategyExtension(this.strategy);

  @override
  TetrisColorsStrategyExtension copyWith({TetrisColorsStrategy? strategy}) {
    return TetrisColorsStrategyExtension(strategy ?? this.strategy);
  }

  @override
  TetrisColorsStrategyExtension lerp(
    ThemeExtension<TetrisColorsStrategyExtension>? other,
    double t,
  ) {
    if (other is! TetrisColorsStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}