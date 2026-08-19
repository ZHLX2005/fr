// Layer 3: GameColorsStrategy ThemeExtension 注入器。

import 'package:flutter/material.dart';

import '../strategy/game_colors_strategy.dart';

class GameColorsStrategyExtension extends ThemeExtension<GameColorsStrategyExtension> {
  final GameColorsStrategy strategy;

  const GameColorsStrategyExtension(this.strategy);

  @override
  GameColorsStrategyExtension copyWith({GameColorsStrategy? strategy}) {
    return GameColorsStrategyExtension(strategy ?? this.strategy);
  }

  @override
  GameColorsStrategyExtension lerp(
    ThemeExtension<GameColorsStrategyExtension>? other,
    double t,
  ) {
    if (other is! GameColorsStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}