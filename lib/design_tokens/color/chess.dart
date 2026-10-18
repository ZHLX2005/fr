// Layer 1 — 国际象棋棋盘 12 角色派生色板。
//
// 全部角色从 ColorScheme 派生（strategy 默认调用，跟主题走）。
// 历史上的 hex 兜底常量已于 2026-10 删除（0 消费者），
// 单一定义处即本文件的 *From(scheme) 方法。
//
// 配色设计要点（v6.2 新增 strategy 通道，专门给 chess 用）：
//   · lightSquare / darkSquare —— 棋盘两色对照，是 chess 的核心识别
//     （不能只走 scheme.surface，因为"两色对照"语义需要固定对比关系）
//   · selectedSquare / legalMoveHint / captureHint —— 三档交互强度
//   · checkWarning —— 用 scheme.error 保持"危险"语义
//   · checkmateOverlay —— 深色 scrim 蒙住棋盘结束游戏
//
// 与 board_color_strategy 的关系：
//   board_color_strategy 是 gomoku / reversi 等通用对弈棋类用，10 角色侧重"黑白子"游戏；
//   chess_color_strategy 是国际象棋专用，12 角色侧重"两色格 + 选中/将军/升变"语义。

import 'package:flutter/material.dart';

class ChessColors {
  ChessColors._();

  // ─── 12 角色 scheme 派生（跟主题）────────────────────────
  //
  // 浅色格 = scheme.surface（页面基底）
  // 深色格 = scheme.surfaceContainerHighest（最抬升，天然比 surface 深一档 → 浅深对照）
  // 这样所有主题自动保留"棋盘两色对比"，但具体颜色跟随主题环境色温：
  //   zen: 浅格暖米 + 深格暖深棕
  //   purple: 浅格鎏金黑 + 深格更深的黑
  //   ink: 浅格纯纸白 + 深格墨黑
  //   rose: 浅格粉灰 + 深格粉棕
  //   lemon: 浅格柠檬白 + 深格橄榄深
  //
  // 用户切主题时 chess 棋盘两色对照语义始终保持，
  // 但具体颜色暖度跟着环境色温变（与 jungle_chess 的 kBoardBg 思路一致）。

  /// 浅色格 —— scheme.surface
  static Color lightSquareFrom(ColorScheme scheme) => scheme.surface;

  /// 深色格 —— scheme.surfaceContainerHighest
  static Color darkSquareFrom(ColorScheme scheme) => scheme.surfaceContainerHighest;

  /// 网格线 —— scheme.outline @ 60% （细线不要太抢眼）
  static Color gridLineFrom(ColorScheme scheme) =>
      scheme.outline.withValues(alpha: 0.6);

  /// 坐标轴 —— scheme.onSurfaceVariant
  static Color coordinateLabelFrom(ColorScheme scheme) =>
      scheme.onSurfaceVariant;

  /// 选中格 —— scheme.primary @ 35% alpha（覆盖在格子上）
  static Color selectedSquareFrom(ColorScheme scheme) =>
      scheme.primary.withValues(alpha: 0.35);

  /// 上一步高亮 —— scheme.primaryContainer @ 70% alpha
  static Color lastMoveHighlightFrom(ColorScheme scheme) =>
      scheme.primaryContainer.withValues(alpha: 0.70);

  /// 合法走法提示 —— scheme.onSurfaceVariant @ 50%（深色圆点）
  static Color legalMoveHintFrom(ColorScheme scheme) =>
      scheme.onSurfaceVariant.withValues(alpha: 0.50);

  /// 吃子走法提示 —— scheme.tertiary（互补色，对比明亮）
  static Color captureHintFrom(ColorScheme scheme) => scheme.tertiary;

  /// 将军警告 —— scheme.error
  static Color checkWarningFrom(ColorScheme scheme) => scheme.error;

  /// 将杀覆盖 —— scheme.scrim（深色压住整盘棋）
  static Color checkmateOverlayFrom(ColorScheme scheme) =>
      scheme.scrim.withValues(alpha: 0.78);

  /// 升变面板 —— scheme.surfaceContainerLow
  static Color promotionOverlayFrom(ColorScheme scheme) =>
      scheme.surfaceContainerLow;

  /// 升变面板边框 —— scheme.outline
  static Color promotionBorderFrom(ColorScheme scheme) => scheme.outline;
}
