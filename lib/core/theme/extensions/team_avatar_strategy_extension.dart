// Layer 3: TeamAvatarStrategy ThemeExtension 注入器。
//
// lerp 50% 阈值切换（识别色锁定）。

import 'package:flutter/material.dart';

import '../colors/strategy/team_avatar_strategy/team_avatar_strategy.dart';

class TeamAvatarStrategyExtension extends ThemeExtension<TeamAvatarStrategyExtension> {
  final TeamAvatarStrategy strategy;

  const TeamAvatarStrategyExtension(this.strategy);

  @override
  TeamAvatarStrategyExtension copyWith({TeamAvatarStrategy? strategy}) {
    return TeamAvatarStrategyExtension(strategy ?? this.strategy);
  }

  @override
  TeamAvatarStrategyExtension lerp(
    ThemeExtension<TeamAvatarStrategyExtension>? other,
    double t,
  ) {
    if (other is! TeamAvatarStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}