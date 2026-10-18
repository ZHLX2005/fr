// Layer 3: TorchProtectColorStrategy ThemeExtension 注入器。
//
// lerp 50% 阈值切换（护眼色随主题离散切换）。

import 'package:flutter/material.dart';

import '../colors/strategy/torch_protect_color_strategy/torch_protect_color_strategy.dart';

class TorchProtectColorStrategyExtension extends ThemeExtension<TorchProtectColorStrategyExtension> {
  final TorchProtectColorStrategy strategy;

  const TorchProtectColorStrategyExtension(this.strategy);

  @override
  TorchProtectColorStrategyExtension copyWith({TorchProtectColorStrategy? strategy}) {
    return TorchProtectColorStrategyExtension(strategy ?? this.strategy);
  }

  @override
  TorchProtectColorStrategyExtension lerp(
    ThemeExtension<TorchProtectColorStrategyExtension>? other,
    double t,
  ) {
    if (other is! TorchProtectColorStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}