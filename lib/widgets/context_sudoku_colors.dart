// BuildContext 扩展：`context.sudokuColors` 快捷访问 SudokuColorStrategy。
//
// 与并行通道平级：
//   context.colors         → 通用 6 角色（accent / surface / outline / text / textMuted / danger）
//   context.boardColors    → 通用对弈棋盘 11 角色（gomoku / reversi / jungle_chess 用）
//   context.chessColors    → 国际象棋专用 13 角色（两色格 + 选中/将军/升变）
//   context.sudokuColors   → 数独专用 8 角色（三态格 + 错误红字 + 笔记候选）
//
// 用途：数独 widget 读 context.sudokuColors.cellBg / cellText / cellSelected 等；
// 普通 UI 类继续用 context.colors.X；
// 其他棋类继续用 context.boardColors.X 或 context.chessColors.X。
//
// 第 7 个 channel：v6.x 新增 sudoku 专用通道，因 sudoku 棋盘需要
// "filled/empty/initial 三态"语义，与 chess 的 "两色格"模型完全不同，
// 强行复用会污染其他棋类。

import 'package:flutter/material.dart';

import '../core/theme/extensions/sudoku_color_strategy_extension.dart';
import '../core/theme/colors/strategy/sudoku_color_strategy/sudoku_color_strategy.dart';
import '../core/theme/colors/strategy/sudoku_color_strategy/themes/default.dart';

extension SudokuColorContext on BuildContext {
  /// 当前生效的 SudokuColorStrategy（双层兜底，绝不返回 null）。
  SudokuColorStrategy get sudokuColors {
    final ext = Theme.of(this).extension<SudokuColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultSudokuColorStrategy.of(Theme.of(this).colorScheme);
  }
}