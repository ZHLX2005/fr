// Layer 3: TorchProtectStrategy ThemeExtension 注入器。
//
// lerp 50% 阈值切换（护眼色随主题离散切换）。

import 'package:flutter/material.dart';

import '../colors/strategy/torch_protect_strategy/torch_protect_strategy.dart';

class TorchProtectStrategyExtension extends ThemeExtension<TorchProtectStrategyExtension> {
  final TorchProtectStrategy strategy;

  const TorchProtectStrategyExtension(this.strategy);

  @override
  TorchProtectStrategyExtension copyWith({TorchProtectStrategy? strategy}) {
    return TorchProtectStrategyExtension(strategy ?? this.strategy);
  }

  @override
  TorchProtectStrategyExtension lerp(
    ThemeExtension<TorchProtectStrategyExtension>? other,
    double t,
  ) {
    if (other is! TorchProtectStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}