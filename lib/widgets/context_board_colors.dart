// BuildContext 扩展：`context.boardColors` 快捷访问 BoardColorStrategy。
//
// 与 `context.colors` 平行：
//   context.colors       → 通用 6 角色（accent / surface / outline / text / textMuted / danger）
//   context.boardColors  → 棋局 10 角色（background / gridLine / axisLabel / player1Stone / ...）
//
// 用途：棋盘类 widget 读 context.boardColors.X；
// 普通 UI 类继续用 context.colors.X。

import 'package:flutter/material.dart';

import '../core/theme/extensions/board_color_strategy_extension.dart';
import '../core/theme/strategy/board_color_strategy.dart';
import '../core/theme/strategy/default_board_color_strategy.dart';

extension BoardColorContext on BuildContext {
  /// 当前生效的 BoardColorStrategy（双层兜底，绝不返回 null）。
  BoardColorStrategy get boardColors {
    final ext = Theme.of(this).extension<BoardColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultBoardColorStrategy.of(Theme.of(this).colorScheme);
  }
}