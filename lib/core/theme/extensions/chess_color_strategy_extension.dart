// Layer 3: 国际象棋 ColorStrategy ThemeExtension 注入器。
//
// 镜像 BoardColorStrategyExtension 的设计：
//   · lerp 用 50% 阈值切换（策略是离散事件，不插值）
//   · 切换主题时 chess 棋盘瞬切，无中间状态
//
// 棋盘两色格、选中格、将军警告等所有 13 角色都是离散语义，不做跨色插值。

import 'package:flutter/material.dart';

import '../colors/strategy/chess_color_strategy/chess_color_strategy.dart';

class ChessColorStrategyExtension
    extends ThemeExtension<ChessColorStrategyExtension> {
  final ChessColorStrategy strategy;

  const ChessColorStrategyExtension(this.strategy);

  @override
  ChessColorStrategyExtension copyWith({ChessColorStrategy? strategy}) {
    return ChessColorStrategyExtension(strategy ?? this.strategy);
  }

  @override
  ChessColorStrategyExtension lerp(
    ThemeExtension<ChessColorStrategyExtension>? other,
    double t,
  ) {
    if (other is! ChessColorStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}
