// BuildContext 扩展：`context.gameColors` 快捷访问 GameColorsStrategy。
//
// 与 `context.colors` / `context.boardColors` 平行：
//   context.colors       → 通用 6 角色
//   context.boardColors  → 棋局 10 角色
//   context.gameColors   → 游戏 7 方块/6 头像/4 护眼

import 'package:flutter/material.dart';

import '../core/theme/extensions/game_colors_strategy_extension.dart';
import '../core/theme/strategy/game_colors_strategy.dart';

extension GameColorContext on BuildContext {
  /// 当前生效的 GameColorsStrategy（双层兜底，绝不返回 null）。
  GameColorsStrategy get gameColors {
    final ext = Theme.of(this).extension<GameColorsStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultGameColorsStrategy.of(Theme.of(this).colorScheme);
  }
}