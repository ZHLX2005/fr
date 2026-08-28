// BuildContext 扩展：`context.tetrisColors` 快捷访问 TetrisColorsStrategy。
//
// 俄罗斯方块统一通道（含棋盘环境 + 方块识别色）：
//   context.tetrisColors.cellHighlight / pieceBackground / pieceGridLine  ← 跟主题
//   context.tetrisColors.pieceColors[i]                                    ← 跨主题锁定

import 'package:flutter/material.dart';

import '../core/theme/extensions/tetris_colors_strategy_extension.dart';
import '../core/theme/colors/strategy/tetris_colors_strategy/tetris_colors_strategy.dart';
import '../core/theme/colors/strategy/tetris_colors_strategy/themes/default.dart';

extension TetrisColorsContext on BuildContext {
  /// 当前生效的 TetrisColorsStrategy（双层兜底，绝不返回 null）。
  TetrisColorsStrategy get tetrisColors {
    final ext = Theme.of(this).extension<TetrisColorsStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultTetrisColorsStrategy.of(Theme.of(this).colorScheme);
  }
}