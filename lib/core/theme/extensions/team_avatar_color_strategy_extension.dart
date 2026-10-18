// Layer 3: TeamAvatarColorStrategy ThemeExtension 注入器。
//
// lerp 50% 阈值切换（识别色锁定）。

import 'package:flutter/material.dart';

import '../colors/strategy/team_avatar_color_strategy/team_avatar_color_strategy.dart';

class TeamAvatarColorStrategyExtension extends ThemeExtension<TeamAvatarColorStrategyExtension> {
  final TeamAvatarColorStrategy strategy;

  const TeamAvatarColorStrategyExtension(this.strategy);

  @override
  TeamAvatarColorStrategyExtension copyWith({TeamAvatarColorStrategy? strategy}) {
    return TeamAvatarColorStrategyExtension(strategy ?? this.strategy);
  }

  @override
  TeamAvatarColorStrategyExtension lerp(
    ThemeExtension<TeamAvatarColorStrategyExtension>? other,
    double t,
  ) {
    if (other is! TeamAvatarColorStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}