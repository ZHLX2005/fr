// Layer 3 — 编译期安全工厂 — 6 个 strategy 的统一构造入口。
//
// 6 个 strategy 角色分工：
//   · ColorStrategy            全局样式（6 角色）：从 scheme 派生，5 主题切换 = 换 scheme
//   · BoardColorStrategy       对弈棋盘（11 角色）：从 scheme + tokens/color/board 派生
//   · ChessColorStrategy       国际象棋棋盘（13 角色）：从 scheme + tokens/color/chess 派生
//   · TetrisColorsStrategy     俄罗斯方块（4 角色）：棋盘 + 方块（识别色锁定）
//   · TeamAvatarStrategy       团队卡 6 头像色（识别色锁定，不跟主题）
//   · TorchProtectStrategy     灯具护眼色（从 scheme 派生）
//
// 单一数据源：scheme 来自 tokens/color/theme/<mode>.dart，
// strategy 仅作为"从 scheme 派生 UI 角色"的规则层，不持有自己的 scheme。

import 'package:flutter/material.dart';

import 'strategy/board_color_strategy/board_color_strategy.dart';
import 'strategy/board_color_strategy/themes/default.dart';
import 'strategy/chess_color_strategy/chess_color_strategy.dart';
import 'strategy/chess_color_strategy/themes/default.dart';
import 'strategy/color_strategy/color_strategy.dart';
import 'strategy/color_strategy/themes/default.dart';
import 'strategy/team_avatar_strategy/team_avatar_strategy.dart';
import 'strategy/team_avatar_strategy/themes/default.dart';
import 'strategy/tetris_colors_strategy/tetris_colors_strategy.dart';
import 'strategy/tetris_colors_strategy/themes/default.dart';
import 'strategy/torch_protect_strategy/torch_protect_strategy.dart';
import 'strategy/torch_protect_strategy/themes/default.dart';

class ThemeStrategyFactory {
  /// 6 角色（context.colors）—— 从 ColorScheme 派生所有 6 角色。
  /// 切主题即换 scheme 实例 → 自动重新派生。
  static ColorStrategy create(ColorScheme scheme) =>
      DefaultColorStrategy(scheme: scheme);

  /// 对弈棋盘 11 角色（context.boardColors）—— 从 scheme 派生。
  static BoardColorStrategy createBoardColorStrategy(ColorScheme scheme) =>
      DefaultBoardColorStrategy.of(scheme);

  /// 国际象棋棋盘 13 角色（context.chessColors）—— 从 scheme 派生。
  static ChessColorStrategy createChessColorStrategy(ColorScheme scheme) =>
      DefaultChessColorStrategy.of(scheme);

  /// 俄罗斯方块 4 角色（context.tetrisColors）—— 棋盘环境从 scheme 派生 + 方块识别色锁定。
  static TetrisColorsStrategy createTetrisColorsStrategy(ColorScheme scheme) =>
      DefaultTetrisColorsStrategy.of(scheme);

  /// 团队卡 6 头像色（context.teamAvatar）—— 识别色锁定，不依赖 scheme。
  static TeamAvatarStrategy createTeamAvatarStrategy() =>
      const DefaultTeamAvatarStrategy();

  /// 灯具护眼色（context.torchProtect）—— 从 scheme 派生。
  static TorchProtectStrategy createTorchProtectStrategy(ColorScheme scheme) =>
      DefaultTorchProtectStrategy.of(scheme);
}