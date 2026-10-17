// BuildContext 扩展：`context.tetrisColors` 快捷访问 TetrisColorStrategy。
//
// 俄罗斯方块统一通道（Ash 纯色井 + 糖果方块）：
//   context.tetrisColors.cellHighlight / pieceBackground / pieceGridLine  ← 跨主题锁定
//   context.tetrisColors.pieceColors[i]                                    ← 跨主题锁定

import 'package:flutter/material.dart';

import '../core/styling/extensions/tetris_color_strategy_extension.dart';
import '../core/styling/colors/strategy/tetris_color_strategy/tetris_color_strategy.dart';
import '../core/styling/colors/strategy/tetris_color_strategy/themes/default.dart';

extension TetrisColorsContext on BuildContext {
  /// 当前生效的 TetrisColorStrategy（双层兜底，绝不返回 null）。
  TetrisColorStrategy get tetrisColors {
    final ext = Theme.of(this).extension<TetrisColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultTetrisColorStrategy.of(Theme.of(this).colorScheme);
  }
}