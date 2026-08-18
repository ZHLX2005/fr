// Layer 3: 棋局 ColorStrategy ThemeExtension 注入器。
//
// 镜像 ColorStrategyExtension 的设计：
//   · lerp 用 50% 阈值切换（策略是离散事件，不插值）
//   · 切换主题时棋盘瞬切，无中间状态

import 'package:flutter/material.dart';

import '../strategy/board_color_strategy.dart';

class BoardColorStrategyExtension extends ThemeExtension<BoardColorStrategyExtension> {
  final BoardColorStrategy strategy;

  const BoardColorStrategyExtension(this.strategy);

  @override
  BoardColorStrategyExtension copyWith({BoardColorStrategy? strategy}) {
    return BoardColorStrategyExtension(strategy ?? this.strategy);
  }

  @override
  BoardColorStrategyExtension lerp(
    ThemeExtension<BoardColorStrategyExtension>? other,
    double t,
  ) {
    if (other is! BoardColorStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}