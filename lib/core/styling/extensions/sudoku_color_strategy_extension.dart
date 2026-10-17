// Layer 3: 数独 ColorStrategy ThemeExtension 注入器。
//
// 镜像 ChessColorStrategyExtension 的设计：
//   · lerp 用 50% 阈值切换（策略是离散事件，不插值）
//   · 切换主题时 sudoku 棋盘瞬切，无中间状态
//
// 数独 8 角色（cellBg 三态 + cellText 二态 + 6 单角色）都是离散语义，
// 不做跨色插值。

import 'package:flutter/material.dart';

import '../colors/strategy/sudoku_color_strategy/sudoku_color_strategy.dart';

class SudokuColorStrategyExtension
    extends ThemeExtension<SudokuColorStrategyExtension> {
  final SudokuColorStrategy strategy;

  const SudokuColorStrategyExtension(this.strategy);

  @override
  SudokuColorStrategyExtension copyWith({SudokuColorStrategy? strategy}) {
    return SudokuColorStrategyExtension(strategy ?? this.strategy);
  }

  @override
  SudokuColorStrategyExtension lerp(
    ThemeExtension<SudokuColorStrategyExtension>? other,
    double t,
  ) {
    if (other is! SudokuColorStrategyExtension) return this;
    return t < 0.5 ? this : other;
  }
}