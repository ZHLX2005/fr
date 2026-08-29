// BuildContext 扩展：`context.chessColors` 快捷访问 ChessColorStrategy。
//
// 与三个并行通道平级：
//   context.colors         → 通用 6 角色（accent / surface / outline / text / textMuted / danger）
//   context.boardColors    → 通用对弈棋盘 11 角色（gomoku / reversi / jungle_chess 用）
//   context.chessColors    → 国际象棋专用 13 角色（两色格 + 选中/将军/升变）
//
// 用途：国际象棋 widget 读 context.chessColors.X；
// 普通 UI 类继续用 context.colors.X；
// 其他棋类继续用 context.boardColors.X。
//
// 第 6 个 channel：v6.2 新增 chess 专用通道，因 international chess 棋盘需要
// "lightSquare / darkSquare 两色对照"语义，与 board_color_strategy 的
// "background 单色底"模型完全不同，强行复用会污染其他棋类。

import 'package:flutter/material.dart';

import '../core/theme/extensions/chess_color_strategy_extension.dart';
import '../core/theme/colors/strategy/chess_color_strategy/chess_color_strategy.dart';
import '../core/theme/colors/strategy/chess_color_strategy/themes/default.dart';

extension ChessColorContext on BuildContext {
  /// 当前生效的 ChessColorStrategy（双层兜底，绝不返回 null）。
  ChessColorStrategy get chessColors {
    final ext = Theme.of(this).extension<ChessColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultChessColorStrategy.of(Theme.of(this).colorScheme);
  }
}
